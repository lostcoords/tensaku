// Tensaku's overlay. Injected by the middleware in development; reads the stamps producers wrote into
// the page and talks to the endpoints under /__tensaku.

import { api, meta } from "./api"
import { contextOf, documentRect, editKind, hasOwnText, isUi, MARKDOWN, nearestStamp, sourceElement, STAMP, stampOf, tagLabel, templateText, translationOf, visibleText, copiesOf } from "./dom"
import { closeEditor, edit, isEditing, undo, undoFor } from "./editor"
import { watch as watchMarkers } from "./markers"
import { currentNotes, deleteAll, drawPins, elementsInArea, load as loadNotes, noteForm, onAgent, onCount, poll as pollNotes, setPinsHidden, sidebarOpen, targetsFor, toggleSidebar } from "./notes"
import { onRefresh } from "./refresh"
import { cursor, icon, type IconName } from "./icons"
import { activeInShadow, box, copy, div, fixed, h, layer, mount, panel, storage, store, toast } from "./ui"

declare global {
  interface Window { __tensaku?: boolean }
}

type Mode = "off" | "inspect" | "edit"
let mode: Mode = "off"
let hoverBoxes: HTMLElement[] = []
let editBoxes: HTMLElement[] = []
let menu: HTMLElement | null = null
let drag: { x: number; y: number; area: HTMLElement | null } | null = null
let suppressClick = false

// Corner button and toolbar ---------------------------------------------------------------------

const count = h("span", { className: "count", hidden: true })
const corner = h("button", { className: "corner", type: "button", title: "Tensaku", "aria-label": "Tensaku", "aria-expanded": "false" }, "添", count)
// Each tool is a drawing from the pencil case, in the colour it marks the page with.
const INK = { highlighter: "#ffe14d", pen: "#e0344f", pad: "#fff1a1" }
function tool(name: IconName, ink: string, text: string, shortcut?: string) {
  const tip = h("span", { className: "tip", "aria-hidden": "true" }, text, shortcut ? h("kbd", {}, shortcut) : null)
  const button = h("button", { type: "button", className: "tool", "aria-pressed": "false", "aria-label": text }, icon(name, ink), tip)
  button.style.setProperty("--ink-color", ink)
  return button
}
const shortcutLabel = () => meta().shortcut.replace(/Key(\w)/, "$1").replace(/Alt/i, "⌥").replace(/Shift/i, "⇧").replace(/Ctrl/i, "⌃").replace(/Meta|Cmd/i, "⌘").replace(/\+/g, "")
const buttons = {
  inspect: tool("highlighter", INK.highlighter, "Select", shortcutLabel()),
  edit: tool("pen", INK.pen, "Edit"),
  notes: tool("pad", INK.pad, "Notes"),
}
const notesBadge = h("span", { className: "badge", hidden: true })
buttons.notes.append(notesBadge)
function action(name: IconName, text: string, shortcut?: string) {
  return h("button", { type: "button", className: "tool", "aria-label": text }, icon(name), h("span", { className: "tip", "aria-hidden": "true" }, text, shortcut ? h("kbd", {}, shortcut) : null))
}
const setTip = (button: HTMLElement, text: string) => {
  button.setAttribute("aria-label", text)
  button.querySelector(".tip")!.firstChild!.textContent = text
}
const pinsTool = action("eye", "Hide pins")
const clearTool = action("trash", "Delete this page's notes")
const closeTool = action("close", "Close", "Esc")
closeTool.setAttribute("aria-label", "Close Tensaku")
// Lit while an agent is connected over MCP (it called a tool in the last few seconds).
const agentLight = h("span", { className: "agent-light", role: "status", hidden: true }, h("span", { className: "tip" }, "Agent connected"))
const toolbar = div("toolbar", agentLight, buttons.inspect, buttons.edit, buttons.notes, div("sep"), pinsTool, clearTool, div("sep"), closeTool)
toolbar.hidden = true
const dock = div("dock", toolbar, corner)
fixed.append(dock)

function placeDock() {
  const position = storage<{ right: number; bottom: number }>("dock", { right: 16, bottom: 16 })
  dock.style.right = `${Math.min(Math.max(position.right, 4), innerWidth - 44)}px`
  dock.style.bottom = `${Math.min(Math.max(position.bottom, 4), innerHeight - 44)}px`
}

let dragged = false
corner.addEventListener("pointerdown", (event) => {
  const start = { x: event.clientX, y: event.clientY, right: parseFloat(dock.style.right), bottom: parseFloat(dock.style.bottom) }
  dragged = false
  corner.setPointerCapture(event.pointerId)
  const move = (e: PointerEvent) => {
    const dx = e.clientX - start.x
    const dy = e.clientY - start.y
    if (!dragged && Math.hypot(dx, dy) < 4) return
    dragged = true
    corner.style.cursor = "grabbing"
    dock.style.right = `${start.right - dx}px`
    dock.style.bottom = `${start.bottom - dy}px`
  }
  const up = () => {
    corner.removeEventListener("pointermove", move)
    corner.removeEventListener("pointerup", up)
    corner.style.cursor = ""
    if (dragged) store("dock", { right: parseFloat(dock.style.right), bottom: parseFloat(dock.style.bottom) })
  }
  corner.addEventListener("pointermove", move)
  corner.addEventListener("pointerup", up)
})
corner.addEventListener("click", () => {
  if (dragged) return
  toolbar.hidden = !toolbar.hidden
  corner.setAttribute("aria-expanded", String(!toolbar.hidden))
  if (toolbar.hidden) setMode("off")
})
buttons.inspect.addEventListener("click", () => setMode(mode === "inspect" ? "off" : "inspect"))
buttons.edit.addEventListener("click", () => setMode(mode === "edit" ? "off" : "edit"))
buttons.notes.addEventListener("click", () => { toggleSidebar(); syncButtons() })
let pinsHidden = storage("pinsHidden", false)
function syncPins() {
  setPinsHidden(pinsHidden)
  pinsTool.setAttribute("aria-pressed", String(pinsHidden))
  pinsTool.replaceChild(icon(pinsHidden ? "eye-off" : "eye"), pinsTool.querySelector("svg")!)
  setTip(pinsTool, pinsHidden ? "Show pins" : "Hide pins")
}
pinsTool.addEventListener("click", () => { pinsHidden = !pinsHidden; store("pinsHidden", pinsHidden); syncPins() })

// Deleting every note on the page takes a second click within three seconds.
let confirmClear = 0
clearTool.addEventListener("click", async () => {
  const total = currentNotes().length
  if (!total) { toast("No notes on this page"); return }
  if (!confirmClear) {
    clearTool.classList.add("confirm")
    setTip(clearTool, `Delete ${total} ${total === 1 ? "note" : "notes"}? Click again`)
    confirmClear = window.setTimeout(resetClear, 3000)
    return
  }
  resetClear()
  try {
    const deleted = await deleteAll()
    toast(`Deleted ${deleted} ${deleted === 1 ? "note" : "notes"}`)
  } catch (error) {
    toast((error as Error).message, { error: true })
  }
})
function resetClear() {
  clearTimeout(confirmClear)
  confirmClear = 0
  clearTool.classList.remove("confirm")
  setTip(clearTool, "Delete this page's notes")
}

onAgent((agent) => {
  agentLight.hidden = !agent.connected
  corner.classList.toggle("agent", agent.connected)
})

closeTool.addEventListener("click", () => { toggleSidebar(false); setMode("off"); toolbar.hidden = true; corner.setAttribute("aria-expanded", "false") })

onCount((n) => {
  count.hidden = n === 0
  count.textContent = String(n)
  notesBadge.hidden = n === 0
  notesBadge.textContent = String(n)
  buttons.notes.setAttribute("aria-label", n ? `Notes (${n})` : "Notes")
  buttons.notes.querySelector(".tip")!.firstChild!.textContent = n ? `Notes (${n})` : "Notes"
})

function syncButtons() {
  buttons.inspect.setAttribute("aria-pressed", String(mode === "inspect"))
  buttons.edit.setAttribute("aria-pressed", String(mode === "edit"))
  buttons.notes.setAttribute("aria-pressed", String(sidebarOpen()))
  corner.classList.toggle("active", mode !== "off")
}

function setMode(next: Mode) {
  mode = next
  if (next !== "inspect" && picked.length) clearPicked()
  if (next !== "off") { toolbar.hidden = false; corner.setAttribute("aria-expanded", "true") }
  clearHover()
  closeMenu()
  drawEditBoxes()
  document.documentElement.style.cursor = next === "inspect" ? cursor("highlighter", INK.highlighter) : next === "edit" ? cursor("pen", INK.pen) : ""
  syncButtons()
}

// Highlights ------------------------------------------------------------------------------------

function clearHover() {
  hoverBoxes.forEach((b) => b.remove())
  hoverBoxes = []
}

function label(element: Element) {
  const stamp = stampOf(element) ?? nearestStamp(element)
  const md = element.getAttribute(MARKDOWN)
  const key = translationOf(element)
  const where = key ? `${key.locale}.${key.key}` : md ? md.split(/:(?=\d+:\d+-)/)[0] + ":" + md.split(/:(?=\d+:\d+-)/)[1].split(":")[0] : stamp ? `${stamp.file}:${stamp.line}` : ""
  return [tagLabel(element), where] as const
}

function highlight(element: Element) {
  clearHover()
  hoverBoxes = box(documentRect(element), mode === "edit" ? "hover-edit" : "", label(element))
}

function editableElements(): Element[] {
  const elements = new Set<Element>()
  document.body.querySelectorAll(`[${STAMP}], [${MARKDOWN}], *`).forEach((element) => {
    if (isUi(element) || !(element as HTMLElement).offsetParent && getComputedStyle(element).position !== "fixed") return
    if (editKind(element)) elements.add(element)
  })
  return Array.from(elements)
}

// Edit mode asks the server once which stamped elements have template text, and draws after the
// answer, so text that comes from Ruby is never outlined.
let asking = false
const EDITABLE_BATCH = 5000

function drawEditBoxes() {
  editBoxes.forEach((b) => b.remove())
  editBoxes = []
  if (mode !== "edit") return
  const elements = editableElements()
  const unknown = Array.from(new Set(elements
    .filter((element) => element.hasAttribute(STAMP) && hasOwnText(element))
    .map((element) => element.getAttribute(STAMP)!)
    .filter((stamp) => !templateText.has(stamp)))).slice(0, EDITABLE_BATCH)
  if (unknown.length) {
    if (asking) return
    asking = true
    api<{ editable: Record<string, boolean> }>("POST", "/editable", { stamps: unknown })
      .then(({ editable }) => unknown.forEach((stamp) => templateText.set(stamp, editable[stamp] ?? false)))
      // Without an answer, outline them all, as before.
      .catch(() => unknown.forEach((stamp) => templateText.set(stamp, true)))
      .finally(() => { asking = false; drawEditBoxes() })
    return
  }
  for (const element of elements) editBoxes.push(...box(documentRect(element), "edit"))
}

// Shift-click in select mode picks several elements for one note --------------------------------

let picked: Element[] = []
let pickedBoxes: HTMLElement[] = []
let pickBar: HTMLElement | null = null

function clearPicked() {
  picked = []
  drawPicked()
}

function togglePicked(element: Element) {
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

function drawPicked() {
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

// Menu after a click in inspect mode ----------------------------------------------------------------

function closeMenu() {
  menu?.remove()
  menu = null
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

function openMenu(element: Element, selectedText?: string) {
  closeMenu()
  const rect = documentRect(element)
  const kind = editKind(element)
  const item = (name: IconName, text: string, action: () => void, shortcut?: string) =>
    h("button", { type: "button", onclick: () => { closeMenu(); action() } }, icon(name), h("span", {}, text), shortcut ? h("kbd", {}, shortcut) : null)
  const undoable = undoFor(element)
  menu = panel(rect, "menu",
    h("h3", {}, label(element)[0], h("span", { className: "where" }, label(element)[1])),
    item("copy", "Copy reference", async () => { await copy(reference(element)); toast("Copied reference") }, "C"),
    item("pad", selectedText ? "Note on selected text" : "Add note", () => noteForm(rect, targetsFor(element, selectedText)), "N"),
    kind ? item(kind === "attributes" ? "tag" : "pen", kind === "attributes" ? "Edit attributes" : "Edit text", () => edit(element, kind), "E") : null,
    kind && kind !== "attributes" && editKind(element) !== "attributes" && hasAttributes(element) ? item("tag", "Edit attributes", () => edit(element, "attributes")) : null,
    undoable ? item("undo", undoable.label, () => undo(element), "U") : null)
  menu.dataset.tensakuMenu = ""
  menu.addEventListener("keydown", (event) => event.stopPropagation())
  ;(menu.querySelector("button") as HTMLElement | null)?.focus()
  menuKeys = (event: KeyboardEvent) => {
    if (!menu) return
    const actions: Record<string, number> = { c: 0, n: 1, e: 2, u: 3 }
    const index = actions[event.key.toLowerCase()]
    if (index === undefined || event.metaKey || event.ctrlKey || event.altKey) return
    const all = Array.from(menu.querySelectorAll("button"))
    const match = all.find((button) => button.querySelector("kbd")?.textContent === event.key.toUpperCase())
    if (match) { event.preventDefault(); match.click() }
  }
  api("POST", "/selection", { url: location.pathname, targets: targetsFor(element, selectedText), text: visibleText(element, 300) }).catch(() => {})
}
let menuKeys: ((event: KeyboardEvent) => void) | null = null

function hasAttributes(element: Element) {
  return ["alt", "title", "placeholder", "aria-label"].some((name) => element.hasAttribute(name))
}

// Page events -----------------------------------------------------------------------------------

function pageTarget(event: Event): Element | null {
  const target = event.composedPath()[0] as Node
  if (isUi(target as Element) || (target instanceof Node && isUi(target.parentElement))) return null
  return sourceElement(target)
}

document.addEventListener("mousemove", (event) => {
  if (drag) return updateDrag(event)
  if (mode === "off" || menu || isEditing()) return
  const element = pageTarget(event)
  if (!element) return clearHover()
  if (mode === "edit" && !editKind(element)) return clearHover()
  highlight(element)
}, true)

document.addEventListener("mousedown", (event) => {
  if (mode !== "inspect" || event.button !== 0 || isUi(event.target as Element) || menu || isEditing()) return
  // Shift would extend the text selection; in select mode it picks elements instead.
  if (event.shiftKey) { event.preventDefault(); return }
  drag = { x: event.pageX, y: event.pageY, area: null }
}, true)

function updateDrag(event: MouseEvent) {
  if (!drag) return
  const width = Math.abs(event.pageX - drag.x)
  const height = Math.abs(event.pageY - drag.y)
  if (!drag.area && Math.hypot(width, height) < 8) return
  if (!drag.area) { clearHover(); drag.area = div("area"); layer.append(drag.area) }
  Object.assign(drag.area.style, { left: `${Math.min(event.pageX, drag.x)}px`, top: `${Math.min(event.pageY, drag.y)}px`, width: `${width}px`, height: `${height}px` })
  event.preventDefault()
}

document.addEventListener("mouseup", (event) => {
  if (!drag) return
  const area = drag.area
  const start = drag
  drag = null
  if (!area) return
  suppressClick = true
  const rect = new DOMRect(Math.min(event.pageX, start.x), Math.min(event.pageY, start.y), Math.abs(event.pageX - start.x), Math.abs(event.pageY - start.y))
  const elements = elementsInArea(rect)
  const highlights = elements.flatMap((element) => box(documentRect(element), "selected"))
  const targets = elements.flatMap((element) => targetsFor(element).slice(0, 1))
  noteForm(rect, targets, { rect: { x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) } }, () => {
    area.remove()
    highlights.forEach((b) => b.remove())
  })
  api("POST", "/selection", { url: location.pathname, targets, text: "" }).catch(() => {})
}, true)

document.addEventListener("click", (event) => {
  if (suppressClick) { suppressClick = false; event.preventDefault(); event.stopPropagation(); return }
  if (isUi(event.target as Element)) return
  const element = pageTarget(event)

  // Alt/Option-click edits right away, in any mode.
  if (event.altKey && element) {
    const kind = editKind(element)
    if (!kind) return
    event.preventDefault()
    event.stopImmediatePropagation()
    closeMenu()
    edit(element, kind)
    return
  }
  if (mode === "off") { if (menu) closeMenu(); return }
  event.preventDefault()
  event.stopImmediatePropagation()
  if (menu || isEditing()) { closeMenu(); return }
  if (!element) return

  if (mode === "edit") {
    const kind = editKind(element)
    if (kind) edit(element, kind)
    return
  }
  if (event.shiftKey) { togglePicked(element); return }
  if (picked.length) clearPicked()
  const selection = getSelection()?.toString().trim()
  openMenu(element, selection && element.contains(getSelection()!.anchorNode) ? selection : undefined)
}, true)

function matchesShortcut(event: KeyboardEvent) {
  const parts = meta().shortcut.split("+")
  const code = parts.pop()!
  const want = new Set(parts.map((p) => p.toLowerCase()))
  return event.code === code && event.altKey === want.has("alt") && event.shiftKey === want.has("shift") &&
    event.ctrlKey === want.has("ctrl") && event.metaKey === (want.has("meta") || want.has("cmd"))
}

document.addEventListener("keydown", (event) => {
  if (matchesShortcut(event)) {
    event.preventDefault()
    setMode(mode === "off" ? "inspect" : "off")
    return
  }
  if (menu && menuKeys) menuKeys(event)
  if (pickBar && !isEditing() && !activeInShadow()?.matches("textarea")) {
    if (event.key.toLowerCase() === "n" && !event.metaKey && !event.ctrlKey && !event.altKey) { event.preventDefault(); notePicked(); return }
    if (event.key === "Escape") { clearPicked(); return }
  }
  if (event.key === "Escape") {
    if (menu) { closeMenu(); return }
    if (isEditing()) return
    if (mode !== "off") setMode("off")
  }
}, true)

// Keeping pins and boxes in place ---------------------------------------------------------------

let redraw = 0
function scheduleRedraw() {
  cancelAnimationFrame(redraw)
  redraw = requestAnimationFrame(() => { drawPins(); drawEditBoxes(); if (picked.length) drawPicked() })
}
addEventListener("resize", () => { placeDock(); scheduleRedraw() })

let path = location.pathname
function pageChanged() {
  closeMenu()
  clearPicked()
  closeEditor()
  clearHover()
  if (location.pathname !== path) { path = location.pathname }
  loadNotes()
  scheduleRedraw()
}
document.addEventListener("turbo:load", pageChanged)
document.addEventListener("turbo:frame-load", scheduleRedraw)
addEventListener("popstate", pageChanged)
// A save can change what a template's elements contain.
onRefresh(() => { templateText.clear(); scheduleRedraw(); loadNotes() })
// Layout shifts (images loading, content changing) move elements; pins follow every second.
setInterval(() => { if (location.pathname !== path) pageChanged(); else drawPins() }, 1000)

// Boot ------------------------------------------------------------------------------------------

function boot() {
  if (window.__tensaku) return
  window.__tensaku = true
  watchMarkers()
  mount()
  placeDock()
  loadNotes()
  pollNotes()
  syncPins()
  // Turbo replaces <body>, not <html>; put the overlay back if something removed it.
  new MutationObserver(() => mount()).observe(document.documentElement, { childList: true })
}

boot()
