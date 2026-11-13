// Notes: comments on elements or areas that an agent reads with the file and line attached. Stored
// by the server in Tensaku's database; this module draws pins, the note form and the notes panel.

import { api, ApiError, isApple, meta, query } from "./api"
import { contentRect, contextOf, MARKDOWN, nearestStamp, STAMP, tagLabel, translationOf, visibleText } from "./dom"
import { textKeys } from "./markers"
import { icon, type IconName } from "./icons"
import { settings } from "./settings"
import { activeInShadow, copy, div, h, layer, fixed, panel, storage, store, toast } from "./ui"
import { capture } from "./screenshot"

interface Target {
  kind: "element" | "text" | "translation" | "markdown"
  stamp?: string
  text?: string
  tag?: string
  key?: string
  locale?: string
  md?: string
  context?: ReturnType<typeof contextOf>
  classes?: string[]
  file?: string
  range?: string
}

export interface Note {
  id: string
  url: string
  comment: string
  targets: Target[]
  rect?: { x: number; y: number; width: number; height: number }
  viewport?: string
  status: "open" | "working" | "question" | "resolved" | "declined"
  sent_at?: string
  // Set when watch_notes handed the note to an agent.
  delivered_at?: string
  delivered_to?: string
  // Set when the page took a screenshot of what the note points at (GET /notes/ID/screenshot).
  screenshot?: { width: number; height: number }
  thread?: { from: "you" | "agent"; text: string; agent?: string; at: string }[]
  agent?: string
  created_at: string
}

// An agent whose `tensaku mcp` is running: where and since when, whether it waits in watch_notes, its
// last tool call and the notes it works on.
export interface Agent {
  name: string
  // Two words from the session id, such as amber-fox. The agent tells the person, so a terminal can
  // be matched to its row.
  handle?: string
  folder?: string
  started_at?: string
  listening: boolean
  last?: { tool: string; note?: string; at: string }
  working: { id: string; url: string; comment: string }[]
}

let notes: Note[] = []
let openCount = 0
let agents: Agent[] = []
const pinLayer = div("pins")
layer.append(pinLayer)
const countListeners: ((count: number) => void)[] = []
const agentListeners: ((agents: Agent[]) => void)[] = []

export const onCount = (listener: (count: number) => void) => countListeners.push(listener)
export const onAgents = (listener: (agents: Agent[]) => void) => agentListeners.push(listener)
export const currentAgents = () => agents

export function setPinsHidden(hidden: boolean) {
  pinLayer.hidden = hidden
}

export async function deleteNotes(list: Note[]) {
  try {
    for (const note of list) await api("DELETE", `/notes/${note.id}`)
  } finally {
    await load({ force: true })
  }
}

// Notes change from outside the page too (an agent starts or resolves one). The dev server streams an
// event whenever the notes or the agents change, and the page loads them then. While the stream is
// down, the page asks every four seconds while the tab is visible (every 16 in a hidden tab with
// notifications on), and reconnects every five. A server that can't stream (501) is only polled.
// Nothing is redrawn when the answer is the same.
let streaming = false
export function poll() {
  let pending = 0
  const changed = () => { clearTimeout(pending); pending = window.setTimeout(() => load(), 30) }
  const connect = async () => {
    let retry = 5000
    try {
      const { token, root } = meta()
      const response = await fetch(root + "/events", { headers: { "X-Tensaku-Token": token, Accept: "text/event-stream" }, credentials: "same-origin" })
      if (response.status === 501) return
      if (!response.ok || !response.body) throw new Error(`events ${response.status}`)
      streaming = true
      const reader = response.body.pipeThrough(new TextDecoderStream()).getReader()
      let buffer = ""
      for (;;) {
        const { value, done } = await reader.read()
        if (done) break
        buffer += value
        const events = buffer.split("\n\n")
        buffer = events.pop() ?? ""
        if (events.some((event) => event.startsWith("data:"))) changed()
      }
    } catch {
      retry = 15000
    }
    streaming = false
    setTimeout(connect, retry)
  }
  const tick = async () => {
    if (!streaming && (document.visibilityState === "visible" || settings().notify)) await load()
    setTimeout(tick, document.visibilityState === "visible" ? 4000 : 16000)
  }
  connect()
  setTimeout(tick, 4000)
}

// The agents waiting in watch_notes.
export const agentLabel = (agent: Agent) => agent.handle ? `${agent.name} · ${agent.handle}` : agent.name
const listeners = () => agents.filter((agent) => agent.listening).map(agentLabel)
// Who a sent note goes to: the one listener by name, or, with several, whichever claims it first.
const sendTarget = () => { const names = listeners(); return names.length === 1 ? names[0] : `the first of ${names.length} listening agents` }

// Changes made from this page, so they aren't announced as the agent's.
const localChanges = new Set<string>()

// The pulsing pin already shows that an agent started on a note, so only these get a toast.
type Change = "resolved" | "declined" | "question" | "message"

// An agent can change many notes between two polls. Toasts appear one at a time, at most three at
// once, and a longer backlog becomes one toast that counts the changes.
const SHOWN_AT_ONCE = 3
const PACE = 1200
const waiting: { note: Note; what: Change }[] = []
let shownToasts: HTMLElement[] = []
let paceTimer = 0

const whoChanged = (note: Note) => note.agent ?? note.thread?.filter((entry) => entry.from === "agent").pop()?.agent ?? "The agent"

function notify(text: string, tag: string) {
  if (document.visibilityState !== "visible" && settings().notify && "Notification" in window && Notification.permission === "granted") {
    new Notification("Tensaku", { body: text, tag })
  }
}

function announceOne(note: Note, what: Change) {
  const who = whoChanged(note)
  const about = `"${note.comment.length > 48 ? note.comment.slice(0, 48) + "…" : note.comment}"`
  const text = { resolved: `${who} resolved ${about}`, declined: `${who} declined ${about}`, question: `${who} has a question on ${about}`, message: `${who} replied on ${about}` }[what]
  notify(text, `tensaku-${note.id}`)
  return toast(text, { actions: { Show: () => { const rect = anchorFor(note); if (rect) { scrollTo({ top: Math.max(0, rect.top - 120), behavior: "smooth" }); showNote(note, rect) } } } })
}

function announceSummary(changes: { note: Note; what: Change }[]) {
  const names = new Set(changes.map((change) => whoChanged(change.note)))
  const who = names.size === 1 ? Array.from(names)[0] : "Agents"
  const count = (what: Change) => changes.filter((change) => change.what === what).length
  const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`
  const parts = [
    count("resolved") && `resolved ${plural(count("resolved"), "note")}`,
    count("declined") && `declined ${plural(count("declined"), "note")}`,
    count("question") && `asked ${plural(count("question"), "question")}`,
    count("message") && `replied on ${plural(count("message"), "note")}`,
  ].filter(Boolean) as string[]
  const text = `${who} ${parts.slice(0, -1).join(", ")}${parts.length > 1 ? " and " : ""}${parts[parts.length - 1]}`
  notify(text, "tensaku-summary")
  return toast(text, { timeout: 8000, actions: { Show: () => toggleSidebar(true) } })
}

function nextAnnouncement() {
  paceTimer = 0
  if (!waiting.length) return
  shownToasts = shownToasts.filter((element) => element.isConnected)
  if (shownToasts.length < SHOWN_AT_ONCE) {
    if (waiting.length > SHOWN_AT_ONCE) shownToasts.push(announceSummary(waiting.splice(0)))
    else { const change = waiting.shift()!; shownToasts.push(announceOne(change.note, change.what)) }
  }
  if (waiting.length) paceTimer = window.setTimeout(nextAnnouncement, PACE)
}

function announce(note: Note, what: Change) {
  // The latest change to a note replaces one still waiting.
  const queued = waiting.findIndex((change) => change.note.id === note.id)
  if (queued >= 0) waiting.splice(queued, 1)
  waiting.push({ note, what })
  // Not shown right away: every change from this poll has to be waiting first to count as a backlog.
  if (!paceTimer) paceTimer = window.setTimeout(nextAnnouncement)
}

function announceChanges(before: Note[], after: Note[]) {
  const old = new Map(before.map((note) => [note.id, note]))
  for (const note of after) {
    const previous = old.get(note.id)
    if (!previous) continue
    if (localChanges.delete(note.id)) continue
    const messages = note.thread?.length ?? 0
    if (messages > (previous.thread?.length ?? 0) && note.thread![messages - 1].from === "agent" && note.status === previous.status) announce(note, "message")
    else if (note.status !== previous.status && note.status !== "open" && note.status !== "working") announce(note, note.status)
  }
}
export const currentNotes = () => notes

// The element's own classes, so an agent can tell why it looks the way it does.
const classesOf = (element: Element) => Array.from(element.classList).filter((name) => !name.startsWith("tensaku")).slice(0, 12)

export function targetsFor(element: Element, selectedText?: string): Target[] {
  const block = element.closest(`[${MARKDOWN}]`)
  const stamped = element.closest(`[${STAMP}]`)
  // A Markdown block inside the nearest stamped element (Kiln renders pages into a layout) points at
  // the source more precisely than that element, so it replaces it.
  if (block && (!stamped || stamped.contains(block))) {
    return [{
      kind: "markdown",
      md: block.getAttribute(MARKDOWN) ?? undefined,
      text: selectedText || visibleText(element, 300),
      tag: tagLabel(element),
      context: contextOf(element),
    }]
  }
  const stamp = nearestStamp(element)
  const base: Target = {
    kind: selectedText ? "text" : "element",
    stamp: stamp?.value,
    text: selectedText || visibleText(element, 300),
    tag: tagLabel(element),
    classes: classesOf(element),
    context: contextOf(element),
  }
  const targets = [base]
  const key = translationOf(element) ?? textKeys(element)[0]?.key
  if (key) targets.push({ kind: "translation", key: key.key, locale: key.locale, text: visibleText(element, 300) })
  const md = element.closest(`[${MARKDOWN}]`)?.getAttribute(MARKDOWN)
  if (md) targets.push({ kind: "markdown", md, text: visibleText(element, 300), tag: tagLabel(element) })
  return targets
}

// The elements an area covers: stamped elements mostly inside the rectangle, outermost first, or the
// innermost element under its center when nothing fits.
export function elementsInArea(rect: DOMRect): Element[] {
  const candidates = Array.from(document.querySelectorAll(`[${STAMP}], [${MARKDOWN}]`)).filter((element) => {
    if (element === document.body || element.closest("[data-tensaku-ui]")) return false
    const box = contentRect(element)
    if (!box.width || !box.height) return false
    const overlap = Math.max(0, Math.min(box.right, rect.right) - Math.max(box.left, rect.left)) * Math.max(0, Math.min(box.bottom, rect.bottom) - Math.max(box.top, rect.top))
    return overlap / (box.width * box.height) >= 0.5
  })
  const outermost = candidates.filter((element) => !candidates.some((other) => other !== element && other.contains(element)))
  if (outermost.length) return outermost.slice(0, 20)
  const center = document.elementFromPoint(rect.left + rect.width / 2 - scrollX, rect.top + rect.height / 2 - scrollY)
  const fallback = center?.closest(`[${STAMP}], [${MARKDOWN}]`)
  return fallback ? [fallback] : []
}

export function noteForm(anchor: DOMRect, targets: Target[], extra: Partial<Note> = {}, onDone?: () => void, heading?: string) {
  // Taken now, before anything moves, and only sent if the box is still ticked on save.
  const shot = capture(anchor)
  const textarea = h("textarea", { rows: 3, placeholder: "What should change?", "aria-label": "Note" })
  const where = targets.filter((t) => t.kind !== "translation" && t.kind !== "markdown").map((t) => t.stamp ?? t.tag).filter(Boolean)
  const close = () => { element.remove(); onDone?.() }
  const picker = agentPicker(storage<string>("send-to", ""))
  const withShot = h("input", { type: "checkbox", checked: storage("screenshots", true), "aria-label": "Attach a screenshot", onchange: () => store("screenshots", withShot.checked) })
  const sendLabel = () => {
    // The menu names the agent, so the button only says Send.
    if (picker) return picker.value || listeners().length ? "Send" : "Save note"
    return listeners().length === 1 ? `Send to ${listeners()[0]}` : listeners().length ? "Send" : "Save note"
  }
  const button = h("button", { type: "button", className: "primary", onclick: () => save() }, sendLabel())
  picker?.addEventListener("change", () => { store("send-to", picker.value); button.textContent = sendLabel() })
  const save = async () => {
    const comment = textarea.value.trim()
    if (!comment) return textarea.focus()
    try {
      const to = picker?.value || undefined
      const note = await api<Note>("POST", "/notes", { url: location.pathname, comment, targets, viewport: `${innerWidth}x${innerHeight}`, to, ...extra })
      close()
      const chosen = agents.find((agent) => agent.handle === to)
      toast(chosen ? `Note sent to ${agentLabel(chosen)}` : listeners().length ? `Note sent to ${sendTarget()}` : "Note saved")
      const png = withShot.checked ? await shot : null
      if (png) await api("PUT", `/notes/${note.id}/screenshot`, { png }).catch((error) => toast(`The screenshot wasn't saved: ${(error as Error).message}`, { error: true }))
      await load()
    } catch (error) {
      toast((error as Error).message, { error: true })
    }
  }
  textarea.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) { event.preventDefault(); save() }
    if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); close() }
  })
  const title = heading ? heading : extra.rect ? `Area, ${targets.length} ${targets.length === 1 ? "element" : "elements"}` : targets[0]?.tag ?? "Note"
  const quoted = !heading && !extra.rect && targets[0]?.text ? `${title} · "${targets[0].text.slice(0, 48)}${targets[0].text.length > 48 ? "…" : ""}"` : title
  const element = panel(anchor, "postit note-form",
    div("head",
      div("what", div("title", quoted), div("where", where.slice(0, 3).join(", ") + (where.length > 3 ? ` and ${where.length - 3} more` : ""))),
      h("button", { type: "button", className: "icon-button", onclick: close, "aria-label": "Cancel" }, icon("close"))),
    textarea,
    div("options",
      h("label", { className: "shot" }, withShot, "Screenshot"),
      picker ? h("label", { className: "to" }, "To", picker) : noAgent()),
    // With an agent listening, saving is sending: the button says to whom.
    div("foot", h("span", { className: "hint" }, `${isApple ? "⌘↵" : "Ctrl+Enter"} ${listeners().length || picker?.value ? "sends" : "saves"}`), h("button", { type: "button", className: "quiet", onclick: close }, "Cancel"), button))
  textarea.focus()
  return element
}

// A menu of the connected agents, listening ones first, or null when none is connected. The empty
// value means the first agent that takes the note.
// The To row with no agent connected: it says so, and opens the Agents popover, which lists the
// commands that start one.
function noAgent() {
  return h("span", { className: "to" }, "To", h("button", { type: "button", className: "link", onclick: () => showAgents() }, "no agent connected, connect one"))
}

function agentPicker(selected: string) {
  const named = agents.filter((agent) => agent.handle)
  if (!named.length) return null
  const ordered = [...named.filter((agent) => agent.listening), ...named.filter((agent) => !agent.listening)]
  const select = h("select", { "aria-label": "Send to" },
    h("option", { value: "" }, listeners().length ? "First listening agent" : "Any agent"),
    ...ordered.map((agent) => h("option", { value: agent.handle! }, `${agentLabel(agent)}${agent.listening ? "" : " (not listening)"}`)))
  select.value = ordered.some((agent) => agent.handle === selected) ? selected : ""
  return select
}

// The server leaves out empty fields, so a note made without targets has none.
const normalized = (list: Note[]) => list.map((note) => ({ ...note, targets: note.targets ?? [] }))

let lastSignature = ""
// Polls and forced loads can overlap; only the newest request's answer is used.
let loadSequence = 0
// A 403 means the page's token no longer matches the server's (tmp/tensaku/token changed). Said once, not on every
// poll; the notes already drawn stay.
let tokenWarned = false
export async function load({ force = false } = {}) {
  const sequence = ++loadSequence
  try {
    const data = await api<{ notes: Note[]; open: number; agents?: Agent[] }>("GET", "/notes" + query({ url: location.pathname }))
    if (sequence !== loadSequence) return
    tokenWarned = false
    agents = data.agents ?? []
    agentListeners.forEach((listener) => listener(agents))
    const signature = location.pathname + JSON.stringify([data.notes, data.open, listeners()])
    if (!force && signature === lastSignature) return
    lastSignature = signature
    if (!primed) data.notes.forEach((note) => drawn.set(note.id, note.status))
    else if (data.notes.length && notes.length) announceChanges(notes, normalized(data.notes))
    primed = true
    notes = normalized(data.notes)
    openCount = data.open
    if (sidebarScope === "all" && sidebar?.isConnected) {
      const all = normalized((await api<{ notes: Note[] }>("GET", "/notes")).notes)
      if (sequence !== loadSequence) return
      allNotes = all
    }
  } catch (error) {
    if (sequence !== loadSequence) return
    if (error instanceof ApiError && error.status === 403 && !tokenWarned) {
      tokenWarned = true
      toast(`${error.message} Notes can't be loaded until then.`, { error: true, timeout: 15000, actions: { Reload: () => location.reload() } })
    }
    return
  }
  countListeners.forEach((listener) => listener(openCount))
  drawPins()
  // A card being edited or answered is left alone when the poll redraws.
  const typing = activeInShadow()?.matches("textarea, input")
  if (sidebar?.isConnected && (force || !(typing && sidebar.contains(activeInShadow())))) renderSidebar()
}

// The selected text a "text" note is about, found again in its element.
function phraseRects(note: Note): DOMRect[] {
  const target = note.targets.find((t) => t.kind === "text" && t.text && t.stamp)
  const element = target && targetElement(target)
  if (!target || !element?.textContent?.includes(target.text!)) return []
  const nodes: Text[] = []
  const starts: number[] = []
  let all = ""
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT)
  while (walker.nextNode()) {
    const node = walker.currentNode as Text
    starts.push(all.length)
    nodes.push(node)
    all += node.data
  }
  const at = all.indexOf(target.text!)
  if (at < 0) return []
  const end = at + target.text!.length
  const lastIndex = (test: (start: number) => boolean) => { for (let i = starts.length - 1; i >= 0; i--) if (test(starts[i])) return i; return 0 }
  const first = lastIndex((start) => start <= at)
  const last = lastIndex((start) => start < end)
  const range = document.createRange()
  range.setStart(nodes[first], at - starts[first])
  range.setEnd(nodes[last], end - starts[last])
  return Array.from(range.getClientRects()).filter((r) => r.width > 0).map((r) => new DOMRect(r.left + scrollX, r.top + scrollY, r.width, r.height))
}

function anchorFor(note: Note): DOMRect | null {
  if (note.rect) return new DOMRect(note.rect.x, note.rect.y, note.rect.width, note.rect.height)
  for (const target of note.targets) {
    const element = targetElement(target)
    if (element) return contentRect(element)
  }
  return null
}

// A stamp is shared by every copy of an element a loop renders; the note belongs to the copy whose
// text it was written about. A stamp is also a line and a column, which go stale when the file changes:
// the element is then looked for by its tag and text elsewhere in the same file. With no match the note
// stays on an element of the same tag at its old position, whose text may have been edited, or nowhere.
function targetElement(target: Target): Element | null {
  const attribute = target.stamp ? STAMP : target.md ? MARKDOWN : null
  const value = target.stamp ?? target.md
  if (!attribute || !value) return null
  const elements = Array.from(document.querySelectorAll(`[${attribute}="${CSS.escape(value)}"]`))
  if (!target.text) return elements[0] ?? null

  const text = target.text.replace(/…$/, "")
  const written = (candidates: Element[]) =>
    candidates.find((element) => visibleText(element, 300) === target.text)
    ?? candidates.find((element) => visibleText(element, 300).startsWith(text))
    ?? candidates.find((element) => target.kind === "text" && element.textContent?.includes(text))
  const here = written(elements)
  if (here) return here

  const tag = target.tag?.split(/[.#]/)[0]
  const sameTag = (element: Element) => !tag || element.tagName.toLowerCase() === tag
  const file = value.match(/^(.+?):\d+/)?.[1]
  const inFile = file ? Array.from(document.querySelectorAll(`[${attribute}^="${CSS.escape(file)}:"]`)).filter(sameTag) : []
  return written(inFile) ?? elements.find(sameTag) ?? null
}

// Pins drop in when a note is added or changes status after the first load.
const drawn = new Map<string, Note["status"]>()
let primed = false
export function drawPins() {
  pinLayer.replaceChildren()
  notes.forEach((note, index) => {
    const phrase = phraseRects(note)
    for (const r of phrase) {
      const mark = div(`phrase ${note.status}`)
      Object.assign(mark.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` })
      pinLayer.append(mark)
    }
    const rect = phrase.length ? phrase[phrase.length - 1] : anchorFor(note)
    if (!rect) return
    const fresh = drawn.get(note.id) !== note.status
    drawn.set(note.id, note.status)
    const pin = h("button", { className: `pin ${note.status}${fresh ? " fresh" : ""}`, title: note.comment, "aria-label": `Note ${index + 1}: ${note.comment}`, "data-note": note.id },
      note.status === "resolved" ? icon("check") : note.status === "declined" ? icon("close") : String(index + 1))
    Object.assign(pin.style, { left: `${rect.right}px`, top: `${rect.top}px` })
    pin.addEventListener("click", (event) => { event.stopPropagation(); showNote(note, rect) })
    pinLayer.append(pin)
  })
}

// One entry per file: _hero.html.erb:4, 9. The full paths are in the tooltip.
function sourceLines(note: Note) {
  const lines = new Map<string, Set<string>>()
  for (const target of note.targets) {
    if (!target.file) continue
    if (!lines.has(target.file)) lines.set(target.file, new Set())
    if (target.range) lines.get(target.file)!.add(target.range.split(/[:-]/)[0])
  }
  const files = Array.from(lines.keys())
  if (!files.length) return null
  const shortened = files.slice(0, 3).map((file) => {
    const numbers = Array.from(lines.get(file)!).join(", ")
    return file.split("/").pop() + (numbers ? `:${numbers}` : "")
  })
  if (files.length > 3) shortened.push(`${files.length - 3} more`)
  return h("div", { className: "source", title: files.join("\n") }, shortened.join(" · "))
}

const STATUS_LABELS = { open: "Open", question: "Question", resolved: "Resolved", declined: "Declined" }
const closed = (note: Note) => note.status === "resolved" || note.status === "declined"

function noteCard(note: Note, onChange = () => {}) {
  // Failures show as a toast; the card stays as it was. update reports whether it saved.
  const attempt = async (run: () => Promise<void>) => {
    try {
      await run()
      return true
    } catch (error) {
      localChanges.delete(note.id)
      toast((error as Error).message, { error: true })
      return false
    }
  }
  const update = (body: Record<string, unknown>) => attempt(async () => { localChanges.add(note.id); await api("PATCH", `/notes/${note.id}`, body); await load({ force: true }); onChange() })
  const remove = () => attempt(async () => { await deleteNotes([note]); onChange() })
  const tool = (name: IconName, label: string, onclick: () => void, className = "") =>
    h("button", { type: "button", className: `icon-button ${className}`, title: label, "aria-label": label, onclick }, icon(name))
  const comment = h("div", { className: "comment" }, note.comment)
  // Editing a note sends it back to the agent as open. The thread stays, as context.
  const startEditing = () => {
    const field = h("textarea", { rows: 3, "aria-label": "Edit note" }, note.comment)
    const saveEdit = async () => {
      const value = field.value.trim()
      if (!value) return field.focus()
      if (value === note.comment) return stopEditing()
      if (await update({ comment: value, status: "open" })) toast("Note updated")
    }
    const stopEditing = () => { editing.replaceWith(comment); actions.hidden = false }
    field.addEventListener("keydown", (event) => {
      event.stopPropagation()
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) { event.preventDefault(); saveEdit() }
      if (event.key === "Escape") { event.preventDefault(); stopEditing() }
    })
    const editing = div("editing", field, div("row", h("button", { type: "button", className: "quiet", onclick: stopEditing }, "Cancel"), h("button", { type: "button", className: "primary", onclick: saveEdit }, "Save")))
    comment.replaceWith(editing)
    actions.hidden = true
    field.focus()
    field.setSelectionRange(field.value.length, field.value.length)
  }
  const here = note.url === location.pathname
  const done = closed(note)
  const actions = div("tools",
    done ? tool("undo", "Reopen", () => update({ status: "open" })) : tool("check", "Mark as done", () => update({ status: "resolved" }), "resolve"),
    tool("pen", "Edit", startEditing),
    tool("trash", "Delete", remove, "delete"))
  // When the agent spoke last (a question, or a reply on a resolved, declined or reopened note), you
  // can answer or ask for changes. Either one sends the note back to the agent as open.
  let answer: Node | null = null
  if (note.status === "question" || note.thread?.at(-1)?.from === "agent") {
    const asked = note.status === "question"
    const label = asked ? "Answer" : "Ask for changes"
    const field = h("textarea", { rows: 2, placeholder: asked ? "Answer the question" : "What should change?", "aria-label": label })
    const send = () => field.value.trim() && update({ message: field.value.trim(), status: "open" })
    field.addEventListener("keydown", (event) => {
      event.stopPropagation()
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) { event.preventDefault(); send() }
    })
    answer = div("answer", field, div("row end", h("button", { type: "button", className: "primary", onclick: send }, label)))
  }
  const thread = threadView(note)
  const missing = !done && here && !anchorFor(note) ? div("missing", "Not found on this page any more.") : null
  const delivered = note.status === "open" && note.delivered_at && note.sent_at && note.delivered_at >= note.sent_at
  const status = note.status === "working" ? `${note.agent ?? "Agent"} is working` : delivered ? `Delivered to ${note.delivered_to}` : STATUS_LABELS[note.status]
  // An open note can be sent again, to an agent session or to whichever agent takes it first: after
  // it was saved with no agent listening, or to move it to another session.
  const owner = agents.find((agent) => agent.handle && agentLabel(agent) === note.agent)
  const picker = note.status === "open" ? agentPicker(owner?.handle ?? "") : null
  const sendTo = async () => {
    const chosen = agents.find((agent) => agent.handle === picker!.value)
    if (await update({ to: picker!.value })) toast(chosen ? `Note sent to ${agentLabel(chosen)}` : "Note sent to the first agent that takes it")
  }
  const sendRow = note.status !== "open" ? null
    : picker ? div("send", h("label", { className: "to" }, "To", picker), h("button", { type: "button", onclick: sendTo }, "Send"))
    : div("send", noAgent())
  return div(`postit note-card ${note.status}`,
    div("head", h("span", { className: `status ${note.status}` }, note.status === "resolved" ? icon("check") : null, status), actions),
    comment,
    screenshotView(note),
    thread,
    missing,
    sendRow,
    answer,
    sourceLines(note))
}

// The screenshot taken with the note, loaded with the token (an <img> can't send it), opening at full
// size on a click.
function screenshotView(note: Note) {
  if (!note.screenshot) return null
  const image = h("img", { alt: "Screenshot", width: note.screenshot.width, height: note.screenshot.height })
  let url = ""
  fetch(`${meta().root}/notes/${note.id}/screenshot`, { headers: { "X-Tensaku-Token": meta().token }, credentials: "same-origin" })
    .then((response) => (response.ok ? response.blob() : null))
    .then((blob) => { if (blob) image.src = url = URL.createObjectURL(blob) })
    .catch(() => {})
  return h("button", { type: "button", className: "screenshot", title: "Open the screenshot", "aria-label": "Open the screenshot", onclick: () => url && open(url, "_blank") }, image)
}

// A long back-and-forth shows the agent's latest message and what came after it, with the earlier
// messages behind a button, as the agent sees it. Opened threads stay open across polls.
const openThreads = new Set<string>()
function threadView(note: Note) {
  const entries = note.thread ?? []
  if (!entries.length) return null
  const lastAgent = entries.map((entry) => entry.from).lastIndexOf("agent")
  const start = openThreads.has(note.id) ? 0 : lastAgent >= 0 ? lastAgent : Math.max(0, entries.length - 2)
  const message = (entry: (typeof entries)[number]) =>
    div(`message ${entry.from}`, h("span", { className: "who" }, entry.from === "you" ? "You" : entry.agent ?? "Agent"), h("span", {}, entry.text))
  const view = div("thread")
  const earlier = start > 0
    ? h("button", { type: "button", className: "link earlier", onclick: () => { openThreads.add(note.id); view.replaceWith(threadView(note)!) } }, `Show ${start} earlier ${start === 1 ? "message" : "messages"}`)
    : null
  if (earlier) view.append(earlier)
  view.append(...entries.slice(start).map(message))
  return view
}

let shown: HTMLElement | null = null
function showNote(note: Note, rect: DOMRect) {
  shown?.remove()
  shown = panel(rect, "note-pop", noteCard(note, () => shown?.remove()))
  const close = (event: Event) => {
    if (!event.composedPath().includes(shown!)) { shown?.remove(); document.removeEventListener("pointerdown", close, true) }
  }
  setTimeout(() => document.addEventListener("pointerdown", close, true))
}

let sidebar: HTMLElement | null = null
export function toggleSidebar(force?: boolean) {
  const show = force ?? !sidebar?.isConnected
  if (!show) { sidebar?.remove(); return }
  sidebar ??= div("sidebar")
  sidebar.setAttribute("role", "complementary")
  sidebar.setAttribute("aria-label", "Tensaku notes")
  fixed.append(sidebar)
  renderSidebar()
}

export const sidebarOpen = () => Boolean(sidebar?.isConnected)

let sidebarScope: "page" | "all" = "page"
let allNotes: Note[] = []

async function showScope(scope: "page" | "all") {
  sidebarScope = scope
  if (scope === "all") allNotes = normalized((await api<{ notes: Note[] }>("GET", "/notes")).notes)
  renderSidebar()
}

// Resolved and declined notes have served their purpose once checked. Archiving moves the ones in the
// panel's scope out of it; agents can still list them, and reopening one brings it back.
async function clearDone(done: Note[]) {
  try {
    await api("POST", "/notes/archive", { ids: done.map((note) => note.id) })
    await load({ force: true })
    toast(`Archived ${done.length} done ${done.length === 1 ? "note" : "notes"}`)
  } catch (error) {
    toast((error as Error).message, { error: true })
  }
}

function renderSidebar() {
  if (!sidebar) return
  const format = settings().copyFormat === "short" ? "short" : undefined
  const copyAll = async (all: boolean) => {
    const markdown = await api<string>("GET", "/notes.md" + query(all ? { format } : { url: location.pathname, format }))
    await copy(markdown)
    toast(all ? "Copied all open notes" : "Copied this page's open notes")
  }
  const tab = (scope: "page" | "all", text: string) =>
    h("button", { type: "button", role: "tab", "aria-selected": String(sidebarScope === scope), onclick: () => showScope(scope) }, text)
  const card = (note: Note) => noteCard(note)
  const scoped = sidebarScope === "page" ? notes : allNotes
  const grouped = (list: Note[]) => sidebarScope === "page"
    ? list.map(card)
    : Array.from(new Set(list.map((note) => note.url))).flatMap((url) => [
        h("a", { className: `page${url === location.pathname ? " current" : ""}`, href: url }, url, h("span", {}, String(list.filter((note) => note.url === url).length))),
        ...list.filter((note) => note.url === url).map(card),
      ])
  const done = scoped.filter(closed)
  const body: Node[] = grouped(scoped.filter((note) => !closed(note)))
  if (done.length) {
    body.push(div("section", h("span", {}, `Done (${done.length})`), h("button", { type: "button", onclick: () => clearDone(done) }, "Archive done")), ...grouped(done))
  } else if (!scoped.length) {
    body.push(div("empty", sidebarScope === "page" ? "No notes on this page. Select an element or drag over an area to add one." : "No notes yet."))
  }
  sidebar.replaceChildren(
    h("header", {}, h("strong", {}, sidebarScope === "page" ? `Notes on ${location.pathname}` : "Notes on every page"), h("button", { type: "button", className: "icon-button", onclick: () => toggleSidebar(false), "aria-label": "Close notes" }, icon("close"))),
    div("tabs", tab("page", "This page"), tab("all", "All pages")),
    ...body,
    ...(openCount ? [sendBar(copyAll)] : []))
}

// The Agents button's popover, opened from the panel when nobody listens.
let showAgents = () => {}
export const setAgentsHandler = (handler: () => void) => { showAgents = handler }

function sendBar(copyAll: (all: boolean) => void) {
  const names = listeners()
  const status = names.length
    ? div("listener on", h("span", { className: "dot" }), `Notes go to ${sendTarget()}`)
    : div("listener", h("span", { className: "dot" }), "No agent listening",
        h("button", { type: "button", className: "link", onclick: () => showAgents() }, "Connect one"))
  // The copy buttons act on the notes above them, so they sit above the rule; who gets the notes is below it.
  return div("copy-bar",
    div("actions",
      h("button", { type: "button", onclick: () => copyAll(false) }, "Copy page"),
      h("button", { type: "button", onclick: () => copyAll(true) }, `Copy all (${openCount})`)),
    status)
}
