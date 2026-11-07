// Notes: comments on elements or areas that an agent reads with the file and line attached. Stored
// by the server in tmp/tensaku/notes; this module draws pins, the note form and the notes panel.

import { api, ApiError, query } from "./api"
import { contentRect, contextOf, MARKDOWN, nearestStamp, STAMP, tagLabel, translationOf, visibleText } from "./dom"
import { textKeys } from "./markers"
import { icon } from "./icons"
import { settings } from "./settings"
import { activeInShadow, copy, div, h, layer, fixed, panel, toast } from "./ui"

export interface Target {
  kind: "element" | "text" | "translation" | "markdown"
  stamp?: string
  text?: string
  tag?: string
  key?: string
  locale?: string
  md?: string
  context?: ReturnType<typeof contextOf>
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
  status: "open" | "working" | "question" | "resolved"
  reply: string | null
  thread?: { from: "you" | "agent"; text: string; agent?: string; at: string }[]
  agent?: string
  created_at: string
}

export interface Agent { connected: boolean; seen_at: string | null; names?: string[] }

let notes: Note[] = []
let openCount = 0
let agent: Agent = { connected: false, seen_at: null }
const pinLayer = div("pins")
layer.append(pinLayer)
const countListeners: ((count: number) => void)[] = []
const agentListeners: ((agent: Agent) => void)[] = []

export const onCount = (listener: (count: number) => void) => countListeners.push(listener)
export const onAgent = (listener: (agent: Agent) => void) => agentListeners.push(listener)

export function setPinsHidden(hidden: boolean) {
  pinLayer.hidden = hidden
}

// Deletes every note on this page. Returns how many were deleted.
export async function deleteAll() {
  const ids = notes.map((note) => note.id)
  for (const id of ids) await api("DELETE", `/notes/${id}`)
  await load({ force: true })
  return ids.length
}

// Notes change from outside the page too (an agent starts or resolves one), so the overlay asks
// again every few seconds while the tab is visible. Nothing is redrawn when the answer is the same.
export function poll() {
  let ticks = 0
  setInterval(() => {
    ticks++
    if (document.visibilityState === "visible" || (settings().notify && ticks % 4 === 0)) load()
  }, 4000)
}

// Moving a note to another element is a pick on the page, which index.ts handles.
let moveHandler: ((note: Note) => void) | null = null
export const setMoveHandler = (handler: (note: Note) => void) => { moveHandler = handler }

export async function moveNote(note: Note, element: Element) {
  localChanges.add(note.id)
  await api("PATCH", `/notes/${note.id}`, { targets: targetsFor(element) })
  toast("Note moved")
  await load({ force: true })
}

// Changes made from this page, so they aren't announced as the agent's.
const localChanges = new Set<string>()

function announce(note: Note, what: "resolved" | "question" | "working" | "message") {
  const who = note.agent ?? note.thread?.filter((entry) => entry.from === "agent").pop()?.agent ?? "The agent"
  const about = `"${note.comment.length > 48 ? note.comment.slice(0, 48) + "…" : note.comment}"`
  const text = { resolved: `${who} resolved ${about}`, question: `${who} has a question on ${about}`, working: `${who} started on ${about}`, message: `${who} replied on ${about}` }[what]
  toast(text, { actions: { Show: () => { const rect = anchorFor(note); if (rect) { scrollTo({ top: Math.max(0, rect.top - 120), behavior: "smooth" }); showNote(note, rect) } } } })
  if (document.visibilityState !== "visible" && settings().notify && "Notification" in window && Notification.permission === "granted") {
    new Notification("Tensaku", { body: text, tag: `tensaku-${note.id}` })
  }
}

function announceChanges(before: Note[], after: Note[]) {
  const old = new Map(before.map((note) => [note.id, note]))
  for (const note of after) {
    const previous = old.get(note.id)
    if (!previous) continue
    if (localChanges.delete(note.id)) continue
    const messages = note.thread?.length ?? 0
    if (messages > (previous.thread?.length ?? 0) && note.thread![messages - 1].from === "agent" && note.status === previous.status) announce(note, "message")
    else if (note.status !== previous.status && note.status !== "open") announce(note, note.status)
  }
}
export const currentNotes = () => notes

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
  const textarea = h("textarea", { rows: 3, placeholder: "What should change?", "aria-label": "Note" })
  const where = targets.filter((t) => t.kind !== "translation" && t.kind !== "markdown").map((t) => t.stamp ?? t.tag).filter(Boolean)
  const close = () => { element.remove(); onDone?.() }
  const save = async () => {
    const comment = textarea.value.trim()
    if (!comment) return textarea.focus()
    try {
      await api("POST", "/notes", { url: location.pathname, comment, targets, viewport: `${innerWidth}x${innerHeight}`, ...extra })
      close()
      toast("Note saved")
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
    div("foot", h("span", { className: "hint" }, "⌘↵ saves"), h("button", { type: "button", className: "quiet", onclick: close }, "Cancel"), h("button", { type: "button", className: "primary", onclick: save }, "Save note")))
  textarea.focus()
  return element
}

// The server leaves out empty fields, so a note made without targets has none.
const normalized = (list: Note[]) => list.map((note) => ({ ...note, targets: note.targets ?? [] }))

let lastSignature = ""
// Polls and forced loads can overlap; only the newest request's answer is used.
let loadSequence = 0
// A 403 means the page's token no longer matches the server's (it restarted). Said once, not on every
// poll; the notes already drawn stay.
let tokenWarned = false
export async function load({ force = false } = {}) {
  const sequence = ++loadSequence
  try {
    const data = await api<{ notes: Note[]; open: number; agent?: Agent }>("GET", "/notes" + query({ url: location.pathname }))
    if (sequence !== loadSequence) return
    tokenWarned = false
    agent = data.agent ?? { connected: false, seen_at: null }
    agentListeners.forEach((listener) => listener(agent))
    const signature = location.pathname + JSON.stringify([data.notes, data.open])
    if (signature === lastSignature) return
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
  if (sidebar?.isConnected && (force || !sidebar.contains(activeInShadow()))) renderSidebar()
}

// The selected text a "text" note is about, found again in its element.
function phraseRects(note: Note): DOMRect[] {
  const target = note.targets.find((t) => t.kind === "text" && t.text && t.stamp)
  const element = target && Array.from(document.querySelectorAll(`[${STAMP}="${CSS.escape(target.stamp!)}"]`)).find((el) => el.textContent?.includes(target.text!))
  if (!target || !element) return []
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
// text it was written about, or the first copy when none matches any more.
function targetElement(target: Target): Element | null {
  const selector = target.stamp ? `[${STAMP}="${CSS.escape(target.stamp)}"]` : target.md ? `[${MARKDOWN}="${CSS.escape(target.md)}"]` : null
  if (!selector) return null
  const elements = Array.from(document.querySelectorAll(selector))
  if (elements.length < 2 || !target.text) return elements[0] ?? null
  const text = target.text.replace(/…$/, "")
  return elements.find((element) => visibleText(element, 300) === target.text)
    ?? elements.find((element) => visibleText(element, 300).startsWith(text))
    ?? elements.find((element) => target.kind === "text" && element.textContent?.includes(text))
    ?? elements[0]
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
      note.status === "resolved" ? icon("check") : String(index + 1))
    Object.assign(pin.style, { left: `${rect.right}px`, top: `${rect.top}px` })
    pin.addEventListener("click", (event) => { event.stopPropagation(); showNote(note, rect) })
    pinLayer.append(pin)
  })
}

function noteCard(note: Note, onChange: () => void) {
  const actions = div("row")
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
  const remove = () => attempt(async () => { await api("DELETE", `/notes/${note.id}`); await load({ force: true }); onChange() })
  const copyNote = () => attempt(async () => { await copy(await api<string>("GET", "/notes.md" + query({ id: note.id, format: settings().copyFormat === "short" ? "short" : undefined }))); toast("Copied note as Markdown") })
  actions.append(h("button", { type: "button", onclick: copyNote }, "Copy"))
  const comment = h("div", { className: "comment" }, note.comment)
  // Editing a note sends it back to the agent: it becomes open again, and an old reply is cleared.
  const startEditing = () => {
    const field = h("textarea", { rows: 3, "aria-label": "Edit note" }, note.comment)
    const saveEdit = async () => {
      const value = field.value.trim()
      if (!value) return field.focus()
      if (value === note.comment) return stopEditing()
      if (await update({ comment: value, status: "open", reply: "" })) toast("Note updated")
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
  actions.append(h("button", { type: "button", onclick: startEditing }, "Edit"))
  const here = note.url === location.pathname
  if (here && moveHandler) actions.append(h("button", { type: "button", onclick: () => { onChange(); moveHandler!(note) } }, "Move"))
  if (note.status === "resolved") {
    actions.append(h("button", { type: "button", onclick: remove }, "Dismiss"), h("button", { type: "button", onclick: () => update({ status: "open" }) }, "Reopen"))
  } else {
    actions.append(h("button", { type: "button", onclick: () => update({ status: "resolved" }) }, "Resolve"), h("button", { type: "button", onclick: remove }, "Delete"))
  }
  // Any note can take a message; answering a question sends the note back as open.
  const answer = note.status !== "resolved" ? h("textarea", { rows: 2, placeholder: note.status === "question" ? "Answer the question" : "Add a message for the agent", "aria-label": "Message" }) : null
  if (answer) {
    answer.addEventListener("keydown", (event) => event.stopPropagation())
    actions.append(h("button", { type: "button", className: "primary", onclick: () => answer.value.trim() && update({ message: answer.value.trim(), status: note.status === "question" ? "open" : undefined }) }, note.status === "question" ? "Answer" : "Send"))
  }
  const thread = note.thread?.length
    ? div("thread", ...note.thread.map((entry) => div(`message ${entry.from}`, h("span", { className: "who" }, entry.from === "you" ? "You" : entry.agent ?? "Agent"), h("span", {}, entry.text))))
    : note.reply ? h("div", { className: `reply ${note.status}` }, note.reply) : null
  const missing = here && !anchorFor(note) ? div("missing", "Not found on this page any more. Move it to the element it's about.") : null
  const files = note.targets.filter((t) => t.file).map((t) => `${t.file}${t.range ? ":" + t.range.split("-")[0] : ""}`)
  return div(`postit note-card ${note.status}`,
    div("row", h("span", { className: `status ${note.status}` }, note.status === "resolved" ? icon("check") : null, note.status === "working" ? `${note.agent ?? "agent"} working` : note.status), h("span", { className: "meta" }, Array.from(new Set(files)).join(", "))),
    comment,
    thread,
    missing,
    answer,
    actions)
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
  let body: Node[]
  if (sidebarScope === "page") {
    body = notes.length ? notes.map((note) => noteCard(note, () => {})) : [div("empty", "No notes on this page. Select an element or drag over an area to add one.")]
  } else {
    const pages = Array.from(new Set(allNotes.map((note) => note.url)))
    body = pages.length
      ? pages.flatMap((url) => [
          h("a", { className: `page${url === location.pathname ? " current" : ""}`, href: url }, url, h("span", {}, String(allNotes.filter((note) => note.url === url).length))),
          ...allNotes.filter((note) => note.url === url).map((note) => noteCard(note, () => {})),
        ])
      : [div("empty", "No notes yet.")]
  }
  sidebar.replaceChildren(
    h("header", {}, h("strong", {}, sidebarScope === "page" ? `Notes on ${location.pathname}` : "Notes on every page"), h("button", { type: "button", className: "icon-button", onclick: () => toggleSidebar(false), "aria-label": "Close notes" }, icon("close"))),
    div("tabs", tab("page", "This page"), tab("all", "All pages")),
    div("row", h("button", { type: "button", onclick: () => copyAll(false) }, "Copy page notes"), h("button", { type: "button", onclick: () => copyAll(true) }, `Copy all open (${openCount})`)),
    ...body)
}
