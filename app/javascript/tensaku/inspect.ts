// Select mode: the highlight under the pointer, walking the stamped elements with the arrow keys, the
// menu a click opens, and Shift-click picking several elements for one note.

import { api, meta, query } from "./api"
import { contextOf, copiesOf, documentRect, editKind, isUi, MARKDOWN, nearestStamp, STAMP, stampOf, tagLabel, translationOf, typingInPage, visibleText } from "./dom"
import { edit, isEditing } from "./editor"
import { undo, undoFor } from "./history"
import { icon, type IconName } from "./icons"
import { mode } from "./mode"
import { noteForm } from "./note-card"
import { targetsFor } from "./note-targets"
import type { Target } from "./notes"
import { activeInShadow, box, copy, h, panel, toast } from "./ui"

// This tab's id, so each tab keeps its own selection for an agent's current_selection.
const TAB = (() => {
  try {
    const id = sessionStorage.getItem("tensaku-tab") ?? Math.random().toString(36).slice(2, 10)
    sessionStorage.setItem("tensaku-tab", id)
    return id
  } catch {
    return Math.random().toString(36).slice(2, 10)
  }
})()

// Tells the server what was selected, for an agent's current_selection.
export function sendSelection(targets: Target[], text: string) {
  api("POST", "/selection", { url: location.pathname, tab: TAB, targets, text }).catch(() => {})
}

// Highlight --------------------------------------------------------------------------------------

let hoverBoxes: HTMLElement[] = []
let current: Element | null = null

export function clearHover() {
  current = null
  hoverBoxes.forEach((b) => b.remove())
  hoverBoxes = []
}

function label(element: Element): readonly [string, string] {
  const stamp = stampOf(element) ?? nearestStamp(element)
  const md = element.getAttribute(MARKDOWN)?.match(/^(.+):(\d+):\d+-/)
  const key = translationOf(element)
  const where = key ? `${key.locale}.${key.key}` : md ? `${md[1]}:${md[2]}` : stamp ? `${stamp.file}:${stamp.line}` : ""
  return [tagLabel(element), where] as const
}

// className "hover-edit" draws the edit mode highlight.
export function highlight(element: Element, className = "") {
  clearHover()
  current = element
  hoverBoxes = box(documentRect(element), className, label(element))
}

// Arrow keys walk the stamped elements from the highlighted one, like a DOM inspector: up to the
// parent, down to the first child, left and right to siblings.
const stamped = (element: Element | null) => Boolean(element && !isUi(element) && element !== document.body && (element.hasAttribute(STAMP) || element.hasAttribute(MARKDOWN)))
function step(element: Element, key: string): Element | null {
  if (key === "ArrowUp") {
    for (let node = element.parentElement; node && node !== document.body; node = node.parentElement) if (stamped(node)) return node
    return null
  }
  if (key === "ArrowDown") return Array.from(element.querySelectorAll(`[${STAMP}], [${MARKDOWN}]`)).find((child) => stamped(child) && (child as HTMLElement).offsetParent !== null) ?? null
  const parent = step(element, "ArrowUp") ?? document.body
  const siblings = Array.from(parent.querySelectorAll(`[${STAMP}], [${MARKDOWN}]`)).filter((node) => stamped(node) && step(node, "ArrowUp") === (parent === document.body ? null : parent))
  const index = siblings.indexOf(element)
  return siblings[index + (key === "ArrowRight" ? 1 : -1)] ?? null
}

// The keys of select mode: arrows walk, Enter opens the menu, Cmd/Ctrl+C copies the reference.
// Returns whether it used the key.
export function selectKey(event: KeyboardEvent): boolean {
  if (mode() !== "inspect" || !current || menu || isEditing() || activeInShadow()?.matches("textarea, input, [contenteditable]") || typingInPage()) return false
  if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(event.key) && !event.altKey && !event.metaKey && !event.ctrlKey) {
    const next = step(current, event.key)
    event.preventDefault()
    if (!next) return true
    highlight(next)
    next.scrollIntoView({ block: "nearest" })
    return true
  }
  if (event.key === "Enter") { event.preventDefault(); openMenu(current); return true }
  // Cmd/Ctrl+C copies the highlighted element's reference, unless page text is selected.
  if (event.key.toLowerCase() === "c" && (event.metaKey || event.ctrlKey) && !getSelection()?.toString()) {
    event.preventDefault()
    const element = current
    copy(reference(element)).then(() => toast("Copied reference"))
    return true
  }
  return false
}

// Shift-click picks several elements for one note ------------------------------------------------

let picked: Element[] = []
let pickedBoxes: HTMLElement[] = []
let pickBar: HTMLElement | null = null

export const hasPicked = () => picked.length > 0

export function clearPicked() {
  picked = []
  drawPicked()
}

export function togglePicked(element: Element) {
  clearHover()
  const index = picked.indexOf(element)
  if (index >= 0) picked.splice(index, 1)
  else picked.push(element)
  drawPicked()
}

function pickedRect() {
  const rects = picked.map(documentRect)
  const left = Math.min(...rects.map((r) => r.left))
  const top = Math.min(...rects.map((r) => r.top))
  return new DOMRect(left, top, Math.max(...rects.map((r) => r.right)) - left, Math.max(...rects.map((r) => r.bottom)) - top)
}

function notePicked() {
  if (!picked.length) return
  const elements = picked
  const targets = elements.flatMap((element) => targetsFor(element).slice(0, 1))
  pickBar?.remove()
  pickBar = null
  noteForm(pickedRect(), targets, {}, clearPicked, `${elements.length} ${elements.length === 1 ? "element" : "elements"}`)
}

export function drawPicked() {
  pickedBoxes.forEach((b) => b.remove())
  pickBar?.remove()
  pickBar = null
  pickedBoxes = picked.flatMap((element, index) => box(documentRect(element), "selected", [`${index + 1}  ${tagLabel(element)}`, ""]))
  if (!picked.length) return
  pickBar = panel(documentRect(picked[picked.length - 1]), "menu pick",
    h("h3", {}, `${picked.length} selected`, h("span", { className: "where" }, "Shift-click to add or remove")),
    h("button", { type: "button", onclick: notePicked }, icon("pad"), h("span", {}, "Add note"), h("kbd", {}, "N")),
    h("button", { type: "button", onclick: clearPicked }, icon("close"), h("span", {}, "Clear"), h("kbd", {}, "Esc")))
  pickBar.dataset.tensakuMenu = ""
}

// N writes the note for the picked elements, Escape clears them. Returns whether it used the key.
export function pickKey(event: KeyboardEvent): boolean {
  if (!pickBar || isEditing() || activeInShadow()?.matches("textarea")) return false
  if (event.key.toLowerCase() === "n" && !event.metaKey && !event.ctrlKey && !event.altKey) { event.preventDefault(); notePicked(); return true }
  if (event.key === "Escape") { clearPicked(); return true }
  return false
}

// The menu after a click -------------------------------------------------------------------------

let menu: HTMLElement | null = null

export const menuOpen = () => menu !== null

export function closeMenu() {
  menu?.remove()
  menu = null
  if (mode() === "off") clearHover()
}

function reference(element: Element): string {
  const stamp = nearestStamp(element)
  const lines = [`${meta().method} ${location.pathname}${location.search} → ${stamp ? `${stamp.file}:${stamp.line}:${stamp.column}` : "(no source stamp)"}`]
  const text = visibleText(element, 200)
  lines.push(`<${tagLabel(element)}>${text ? ` "${text}"` : ""}`)
  const key = translationOf(element)
  if (key) lines.push(`Translation: ${key.locale}.${key.key}`)
  const md = element.closest(`[${MARKDOWN}]`)?.getAttribute(MARKDOWN)
  if (md) lines.push(`Markdown: ${md}`)
  const context = contextOf(element)
  if (context.partials.length > 1) lines.push(`Partials: ${context.partials.join(" < ")}`)
  if (context.controller) lines.push(`Stimulus: ${context.controller}`)
  if (context.frame) lines.push(`Turbo Frame: #${context.frame}`)
  const copies = copiesOf(element)
  if (copies > 1) lines.push(`Rendered ${copies} times on this page (loop or repeated partial)`)
  return lines.join("\n")
}

const hasAttributes = (element: Element) => ["alt", "title", "placeholder", "aria-label"].some((name) => element.hasAttribute(name))

// The menu and its note form open at `at`, the click point, and below the element without one.
export function openMenu(element: Element, selectedText?: string, at?: DOMRect) {
  closeMenu()
  const rect = documentRect(element)
  const spot = at ?? rect
  const kind = editKind(element)
  const item = (name: IconName, text: string, action: () => void, shortcut?: string) =>
    h("button", { type: "button", onclick: () => { closeMenu(); action() } }, icon(name), h("span", {}, text), shortcut ? h("kbd", {}, shortcut) : null)
  const undoable = undoFor(element)
  const list = element.closest(`ul[${MARKDOWN}], ol[${MARKDOWN}]`)
  const [tag, where] = label(element)
  menu = panel(spot, "menu",
    h("h3", {}, tag, h("span", { className: "where" }, where)),
    kind ? item(kind === "attributes" ? "tag" : "pen", kind === "attributes" ? "Edit attributes" : "Edit text", () => edit(element, kind), "E") : null,
    kind && kind !== "attributes" && hasAttributes(element) ? item("tag", "Edit attributes", () => edit(element, "attributes")) : null,
    list && list !== element ? item("pen", "Edit the whole list", () => edit(list, "markdown"), "L") : null,
    item("pad", selectedText ? "Note on selected text" : "Add note", () => noteForm(rect, targetsFor(element, selectedText), {}, undefined, undefined, spot), "N"),
    item("copy", "Copy reference", async () => { await copy(reference(element)); toast("Copied reference") }, "C"),
    undoable ? item("undo", `Undo ${undoable.label}`, () => undo(undoable), "U") : null,
    item("code", "Open in editor", () => openInEditor(element), "O"))
  menu.dataset.tensakuMenu = ""
  menu.addEventListener("keydown", (event) => event.stopPropagation())
  ;(menu.querySelector("button") as HTMLElement | null)?.focus()
  sendSelection(targetsFor(element, selectedText), visibleText(element, 300))
}

// A letter presses the menu item with that shortcut.
export function menuKey(event: KeyboardEvent) {
  if (!menu || event.key.length !== 1 || !"cneluo".includes(event.key.toLowerCase()) || event.metaKey || event.ctrlKey || event.altKey) return
  const match = Array.from(menu.querySelectorAll("button")).find((button) => button.querySelector("kbd")?.textContent === event.key.toUpperCase())
  if (match) { event.preventDefault(); match.click() }
}

// Opens the element's file in the editor Rails knows from RAILS_EDITOR or EDITOR.
async function openInEditor(element: Element) {
  const md = element.closest(`[${MARKDOWN}]`)?.getAttribute(MARKDOWN)?.match(/^(.+):(\d+):\d+-/)
  const stamp = nearestStamp(element)
  const [file, line] = md && (!stamp || element.closest(`[${STAMP}]`)?.contains(element.closest(`[${MARKDOWN}]`))) ? [md[1], md[2]] : stamp ? [stamp.file, String(stamp.line)] : []
  if (!file) return toast("This element has no source position.", { error: true })
  try {
    const { url } = await api<{ url: string | null }>("GET", "/editor" + query({ file, line }))
    if (url) location.href = url
    else toast(`Set RAILS_EDITOR (vscode, cursor, zed, …) to open files from here. ${file}:${line}`, { timeout: 8000 })
  } catch (error) {
    toast((error as Error).message, { error: true })
  }
}
