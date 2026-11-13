// A note's card (in the notes panel, or opened from its pin) and the form that writes a new note.

import { api, isApple, meta } from "./api"
import { icon, type IconName } from "./icons"
import { anchorFor } from "./note-targets"
import { agentLabel, closed, currentAgents, currentNotes, deleteLater, load, type Note, onRender, type Target, updateNote, type NoteChange } from "./notes"
import { capture } from "./screenshot"
import { activeInShadow, div, h, panel, storage, store, toast } from "./ui"

// The Agents button's popover, which lists the commands that start an agent. index.ts sets it.
let showAgents = () => {}
export const setAgentsHandler = (handler: () => void) => { showAgents = handler }
export const openAgents = () => showAgents()

// `anchor` is what the screenshot captures; `at` is where the form opens, the click point when there is one.
export function noteForm(anchor: DOMRect, targets: Target[], extra: Partial<Note> = {}, onDone?: () => void, heading?: string, at = anchor) {
  // Taken now, before anything moves, and only sent if the box is still ticked on save.
  const shot = capture(anchor)
  const textarea = h("textarea", { rows: 3, placeholder: "What should change?", "aria-label": "Note" })
  const where = targets.filter((t) => t.kind !== "translation" && t.kind !== "markdown").map((t) => t.stamp ?? t.tag).filter(Boolean)
  const close = () => { element.remove(); onDone?.() }
  const picker = agentPicker(storage<string>("assign-to", ""))
  const withShot = h("input", { type: "checkbox", checked: storage("screenshots", true), "aria-label": "Attach a screenshot", onchange: () => store("screenshots", withShot.checked) })
  const button = h("button", { type: "button", className: "primary", onclick: () => save() }, "Save note")
  picker?.addEventListener("change", () => store("assign-to", picker.value))
  const save = async () => {
    const comment = textarea.value.trim()
    if (!comment) return textarea.focus()
    try {
      const to = picker?.value || undefined
      const note = await api<Note>("POST", "/notes", { url: location.pathname, comment, targets, viewport: `${innerWidth}x${innerHeight}`, to, ...extra })
      close()
      const chosen = currentAgents().find((agent) => agent.handle === to)
      toast(chosen ? `Note saved and assigned to ${agentLabel(chosen)}` : "Note saved")
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
  const element = panel(at, "postit note-form",
    div("head",
      div("what", div("title", quoted), div("where", where.slice(0, 3).join(", ") + (where.length > 3 ? ` and ${where.length - 3} more` : ""))),
      h("button", { type: "button", className: "icon-button", onclick: close, "aria-label": "Cancel" }, icon("close"))),
    textarea,
    div("options",
      h("label", { className: "shot" }, withShot, "Screenshot"),
      picker ? h("label", { className: "to" }, "Assign to", picker) : noAgent()),
    div("foot", h("span", { className: "hint" }, `${isApple ? "⌘↵" : "Ctrl+Enter"} saves`), h("button", { type: "button", className: "quiet", onclick: close }, "Cancel"), button))
  textarea.focus()
  return element
}

// The Assign row with no agent connected: it says so, and opens the Agents popover, which lists the
// commands that start one.
function noAgent() {
  return h("span", { className: "to" }, "Assign to", h("button", { type: "button", className: "link", onclick: openAgents }, "no agent connected, connect one"))
}

// A menu of the connected agent sessions, listening ones first, or null when none is connected. The
// empty value leaves the note unassigned: the first session that checks for notes takes it.
function agentPicker(selected: string) {
  const named = currentAgents().filter((agent) => agent.handle)
  if (!named.length) return null
  const ordered = [...named.filter((agent) => agent.listening), ...named.filter((agent) => !agent.listening)]
  const select = h("select", { "aria-label": "Assign to" },
    h("option", { value: "" }, "Anyone"),
    ...ordered.map((agent) => h("option", { value: agent.handle! }, `${agentLabel(agent)}${agent.listening ? "" : " (not listening)"}`)))
  select.value = ordered.some((agent) => agent.handle === selected) ? selected : ""
  return select
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

// onChange(note) is called with the note's new state, or without one once it is deleted.
export function noteCard(note: Note, onChange: (note?: Note) => void = () => {}) {
  const update = (change: NoteChange) => updateNote(note, change, onChange)
  const remove = () => { deleteLater(note); onChange() }
  // Done and reopen are one click, so each toast can put the note back as it was.
  const setStatus = async (status: Note["status"], said: string) => {
    const before = note.status
    if (await update({ status })) toast(said, { actions: { Undo: () => update({ status: before }) } })
  }
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
    done ? h("button", { type: "button", className: "reopen", title: "Reopen: back to open, without sending it to an agent", "aria-label": "Reopen", onclick: () => setStatus("open", "Note reopened") }, "Reopen")
      : tool("check", "Mark as done", () => setStatus("resolved", "Marked as done"), "resolve"),
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
  // An open note assigned to one session says so until that session picks it up. A note in progress
  // whose session's process ended says so: anyone can take it.
  const status = note.status === "working" ? (note.stopped ? `${note.agent ?? "Agent"} stopped. Anyone can take it` : `${note.agent ?? "Agent"} is working`)
    : delivered ? `Picked up by ${note.delivered_to}`
    : note.status === "open" ? (note.agent ? `Assigned to ${note.agent}` : "Unassigned") : STATUS_LABELS[note.status]
  // An open note can be assigned to a session or left to anyone. A note in progress can be taken back
  // the same way, for an agent you stopped mid-work: the note is open again, and that session's
  // resolve is refused.
  const owner = currentAgents().find((agent) => agent.handle && agentLabel(agent) === note.agent)
  const assignable = note.status === "open" || note.status === "working"
  const picker = assignable ? agentPicker(note.status === "open" ? owner?.handle ?? "" : "") : null
  // The handle the note is assigned to now; on a note in progress, nobody yet in the menu's terms.
  const current = note.status === "open" ? owner?.handle ?? "" : null
  const assign = async () => {
    const chosen = currentAgents().find((agent) => agent.handle === picker!.value)
    const undo = current === null ? undefined : { Undo: () => update({ to: current }) }
    if (await update({ to: picker!.value })) {
      toast(chosen ? `Note assigned to ${agentLabel(chosen)}` : "Note unassigned: the first session that checks takes it", { actions: undo })
    }
  }
  const assignButton = h("button", { type: "button", onclick: assign })
  // Says when the menu already shows who has the note, so a click that changes nothing isn't offered.
  const syncAssign = () => {
    const same = picker?.value === current
    assignButton.disabled = same
    assignButton.textContent = same ? "Assigned" : note.status === "working" ? "Reassign" : "Assign"
  }
  picker?.addEventListener("change", syncAssign)
  syncAssign()
  const assignRow = !assignable ? null
    : picker ? div("assign", h("label", { className: "to" }, "Assign to", picker), assignButton)
    : div("assign", noAgent())
  const statusLabel = h("span", {}, status)
  return div(`postit note-card ${note.status}`,
    div("head", h("span", { className: `status ${note.status}` }, note.status === "resolved" ? icon("check") : null, statusLabel), actions),
    comment,
    screenshotView(note),
    thread,
    missing,
    assignRow,
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

// The note card opened from a pin, and the note it shows. It follows the note's changes, from this
// page or from an agent, unless you are typing in it.
let shown: HTMLElement | null = null
let shownNote: Note | null = null
export function showNote(note: Note, rect?: DOMRect) {
  const onChange = (next?: Note) => { if (!next) shown?.remove() }
  if (!rect) {
    if (!shown?.isConnected) return
    shownNote = note
    shown.replaceChildren(noteCard(note, onChange))
    return
  }
  shown?.remove()
  shownNote = note
  shown = panel(rect, "note-pop", noteCard(note, onChange))
  const close = (event: Event) => {
    if (!event.composedPath().includes(shown!)) { shown?.remove(); document.removeEventListener("pointerdown", close, true) }
  }
  setTimeout(() => document.addEventListener("pointerdown", close, true))
}

onRender(({ changed }) => {
  if (changed) {
    if (shownNote?.id === changed.id) showNote(changed)
    return
  }
  if (!shown?.isConnected || !shownNote) return
  const latest = currentNotes().find((note) => note.id === shownNote!.id)
  if (!latest || JSON.stringify(latest) === JSON.stringify(shownNote)) return
  const typing = activeInShadow()
  if (typing?.matches("textarea, input") && shown.contains(typing) && (typing as HTMLTextAreaElement).value) return
  showNote(latest)
})
