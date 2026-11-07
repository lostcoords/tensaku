// Notes: comments on elements or areas that an agent reads with the file and line attached. Stored
// by the server in tmp/tensaku/notes; this module draws pins, the note form and the notes panel.

import { api, query } from "./api"
import { contentRect, contextOf, MARKDOWN, nearestStamp, STAMP, tagLabel, translationOf, visibleText } from "./dom"
import { textKeys } from "./markers"
import { icon } from "./icons"
import { copy, div, h, layer, fixed, panel, toast } from "./ui"

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
  status: "open" | "question" | "resolved"
  reply: string | null
  created_at: string
}

let notes: Note[] = []
let openCount = 0
const pinLayer = div("pins")
layer.append(pinLayer)
const countListeners: ((count: number) => void)[] = []

export const onCount = (listener: (count: number) => void) => countListeners.push(listener)
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

export function noteForm(anchor: DOMRect, targets: Target[], extra: Partial<Note> = {}, onDone?: () => void) {
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
const title = extra.rect ? `Area, ${targets.length} ${targets.length === 1 ? "element" : "elements"}` : targets[0]?.tag ?? "Note"
const quoted = !extra.rect && targets[0]?.text ? `${title} · "${targets[0].text.slice(0, 48)}${targets[0].text.length > 48 ? "…" : ""}"` : title
const saveButton = h("button", { type: "button", className: "primary", onclick: save }, "Save note")
const element = panel(anchor, "postit note-form",
  div("head",
    div("what", div("title", quoted), div("where", where.slice(0, 3).join(", ") + (where.length > 3 ? ` and ${where.length - 3} more` : ""))),
    h("button", { type: "button", className: "icon-button", onclick: close, "aria-label": "Cancel" }, icon("close"))),
  textarea,
  div("foot", h("span", { className: "hint" }, "⌘↵ saves"), h("button", { type: "button", className: "quiet", onclick: close }, "Cancel"), saveButton))
  textarea.focus()
  return element
}

export async function load() {
  try {
    const data = await api<{ notes: Note[]; open: number }>("GET", "/notes" + query({ url: location.pathname }))
    if (!primed) data.notes.forEach((note) => drawn.set(note.id, note.status))
    primed = true
    notes = data.notes
    openCount = data.open
  } catch {
    notes = []
  }
  countListeners.forEach((listener) => listener(openCount))
  drawPins()
  if (sidebar?.isConnected) renderSidebar()
}

function anchorFor(note: Note): DOMRect | null {
  if (note.rect) return new DOMRect(note.rect.x, note.rect.y, note.rect.width, note.rect.height)
  for (const target of note.targets) {
    const selector = target.stamp ? `[${STAMP}="${CSS.escape(target.stamp)}"]` : target.md ? `[${MARKDOWN}="${CSS.escape(target.md)}"]` : null
    const element = selector && document.querySelector(selector)
    if (element) return contentRect(element)
  }
  return null
}

// Pins drop in when a note is added or changes status after the first load.
const drawn = new Map<string, Note["status"]>()
let primed = false
export function drawPins() {
  pinLayer.replaceChildren()
  notes.forEach((note, index) => {
    const rect = anchorFor(note)
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
  const update = async (body: Record<string, unknown>) => { await api("PATCH", `/notes/${note.id}`, body); await load(); onChange() }
  const remove = async () => { await api("DELETE", `/notes/${note.id}`); await load(); onChange() }
  actions.append(h("button", { type: "button", onclick: async () => { await copy(await api<string>("GET", "/notes.md" + query({ id: note.id }))); toast("Copied note as Markdown") } }, "Copy"))
  if (note.status === "resolved") {
    actions.append(h("button", { type: "button", onclick: remove }, "Dismiss"), h("button", { type: "button", onclick: () => update({ status: "open" }) }, "Reopen"))
  } else {
    actions.append(h("button", { type: "button", onclick: () => update({ status: "resolved" }) }, "Resolve"), h("button", { type: "button", onclick: remove }, "Delete"))
  }
  const answer = note.status === "question" ? h("textarea", { rows: 2, placeholder: "Answer the question (updates the note)" }) : null
  if (answer) {
    actions.append(h("button", { type: "button", className: "primary", onclick: () => answer.value.trim() && update({ status: "open", comment: `${note.comment}\n\nAnswer: ${answer.value.trim()}`, reply: "" }) }, "Answer"))
  }
  const files = note.targets.filter((t) => t.file).map((t) => `${t.file}${t.range ? ":" + t.range.split("-")[0] : ""}`)
  return div(`postit note-card ${note.status}`,
    div("row", h("span", { className: `status ${note.status}` }, note.status === "resolved" ? icon("check") : null, note.status), h("span", { className: "meta" }, Array.from(new Set(files)).join(", "))),
    h("div", { className: "comment" }, note.comment),
    note.reply ? h("div", { className: `reply ${note.status}` }, note.reply) : null,
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

function renderSidebar() {
  if (!sidebar) return
  const copyAll = async (all: boolean) => {
    const markdown = await api<string>("GET", "/notes.md" + query(all ? {} : { url: location.pathname }))
    await copy(markdown)
    toast(all ? "Copied all open notes" : "Copied this page's open notes")
  }
  sidebar.replaceChildren(
    h("header", {}, h("strong", {}, `Notes on ${location.pathname}`), h("button", { type: "button", className: "icon-button", onclick: () => toggleSidebar(false), "aria-label": "Close notes" }, icon("close"))),
    div("row", h("button", { type: "button", onclick: () => copyAll(false) }, "Copy page notes"), h("button", { type: "button", onclick: () => copyAll(true) }, `Copy all open (${openCount})`)),
    ...(notes.length ? notes.map((note) => noteCard(note, () => {})) : [div("empty", "No notes on this page. Select an element or drag over an area to add one.")]))
}
