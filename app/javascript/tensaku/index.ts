// Tensaku's overlay. Injected by the middleware in development; reads the stamps producers wrote into
// the page and talks to the endpoints under /__tensaku.

import { api, isApple, meta, query } from "./api"
import { contextOf, documentRect, editKind, hasOwnText, isUi, MARKDOWN, nearestStamp, sourceElement, STAMP, stampOf, tagLabel, templateText, translationOf, visibleText, copiesOf } from "./dom"
import { closeEditor, edit, editHistory, isEditing, undo, undoFor } from "./editor"
import { watch as watchMarkers } from "./markers"
import { currentNotes, deleteAll, drawPins, elementsInArea, load as loadNotes, moveNote, noteForm, onAgent, onCount, poll as pollNotes, setMoveHandler, setPinsHidden, sidebarOpen, targetsFor, toggleSidebar, type Note } from "./notes"
import { changeSettings, onSettings, settings } from "./settings"
import { onRefresh } from "./refresh"
import { cursor, icon, type IconName } from "./icons"
import { activeInShadow, box, copy, div, fixed, h, layer, mount, panel, storage, store, toast } from "./ui"

declare global {
  interface Window { __tensaku?: boolean }
}

// Listeners on the page (document and window) and timers are only added by boot(), after its guard, so
// a second copy of this script on the page adds nothing. Listeners on the overlay's own elements stay
// inline: a second copy's elements are never mounted.
const pending: (() => void)[] = []
function onDocument<K extends keyof DocumentEventMap>(type: K, listener: (event: DocumentEventMap[K]) => void, options?: boolean | AddEventListenerOptions): void
function onDocument(type: string, listener: (event: Event) => void, options?: boolean | AddEventListenerOptions): void
function onDocument(type: string, listener: (event: any) => void, options?: boolean | AddEventListenerOptions) {
  pending.push(() => document.addEventListener(type, listener, options))
}
function onWindow<K extends keyof WindowEventMap>(type: K, listener: (event: WindowEventMap[K]) => void) {
  pending.push(() => addEventListener(type, listener))
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
const APPLE_KEYS: Record<string, string> = { alt: "⌥", shift: "⇧", ctrl: "⌃", meta: "⌘", cmd: "⌘" }
const OTHER_KEYS: Record<string, string> = { alt: "Alt", shift: "Shift", ctrl: "Ctrl", meta: "Meta", cmd: "Meta" }
// The configured shortcut in the platform's own notation: ⌥⇧T on Apple platforms, Alt+Shift+T elsewhere.
function shortcutLabel() {
  const parts = meta().shortcut.split("+")
  const key = parts.pop()!.replace(/^Key/, "")
  const names = isApple ? APPLE_KEYS : OTHER_KEYS
  return [ ...parts.map((part) => names[part.toLowerCase()] ?? part), key ].join(isApple ? "" : "+")
}
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
const historyTool = action("history", "Edit history")
const settingsTool = action("gear", "Settings")
const closeTool = action("close", "Close", "Esc")
closeTool.setAttribute("aria-label", "Close Tensaku")
// Lit while an agent is connected over MCP (it called a tool in the last few seconds).
const agentLight = h("span", { className: "agent-light", role: "status", hidden: true }, h("span", { className: "tip" }, "Agent connected"))
const toolbar = div("toolbar", agentLight, buttons.inspect, buttons.edit, buttons.notes, div("sep"), pinsTool, clearTool, historyTool, settingsTool, div("sep"), closeTool)
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
  const names = agent.names ?? []
  agentLight.firstChild!.textContent = names.length ? `${names.join(", ")} connected` : "Agent connected"
})

// Popovers above the toolbar: one at a time, closed by a second click, Escape or a click elsewhere.
let popover: HTMLElement | null = null
let popoverTool: HTMLElement | null = null
function closePopover() {
  popover?.remove()
  popover = null
  popoverTool?.setAttribute("aria-pressed", "false")
  popoverTool = null
}
function openPopover(tool: HTMLElement, render: () => Node[]) {
  const same = popoverTool === tool
  closePopover()
  if (same) return
  popover = div("popover", ...render())
  popover.addEventListener("keydown", (event) => event.stopPropagation())
  dock.append(popover)
  popoverTool = tool
  tool.setAttribute("aria-pressed", "true")
}
onDocument("pointerdown", (event) => {
  if (popover && !event.composedPath().some((node) => node === popover || node === popoverTool)) closePopover()
}, true)

const ago = (date: Date) => {
  const seconds = Math.round((Date.now() - date.getTime()) / 1000)
  return seconds < 60 ? "just now" : seconds < 3600 ? `${Math.round(seconds / 60)} min ago` : `${Math.round(seconds / 3600)} h ago`
}
function renderHistory(): Node[] {
  const entries = editHistory()
  return [
    h("h3", {}, "Edit history", h("span", { className: "where" }, "Saves since this page loaded. Each element can undo its latest edit.")),
    ...(entries.length ? entries.map((entry) => div(`entry${entry.undone ? " undone" : ""}`,
      div("what", h("span", {}, entry.label), h("span", { className: "where" }, `${entry.file ?? ""} · ${ago(entry.at)}`)),
      entry.canUndo
        ? h("button", { type: "button", onclick: async () => { await entry.run(); closePopover() } }, "Undo")
        : h("span", { className: "where" }, entry.undone ? "undone" : "edited again"))) : [div("empty", "No edits yet.")]),
  ]
}
historyTool.addEventListener("click", () => openPopover(historyTool, renderHistory))

function renderSettings(): Node[] {
  const prefs = settings()
  const choice = (value: "detailed" | "short", text: string) =>
    h("button", { type: "button", "aria-pressed": String(prefs.copyFormat === value), onclick: () => { changeSettings({ copyFormat: value }); refreshPopover() } }, text)
  const check = (checked: boolean, text: string, hint: string, change: (on: boolean) => void) => {
    const input = h("input", { type: "checkbox", checked })
    input.addEventListener("change", () => change(input.checked))
    return h("label", { className: "check" }, input, h("span", {}, text, h("span", { className: "where" }, hint)))
  }
  return [
    h("h3", {}, "Settings", h("span", { className: "where" }, "Kept in this browser.")),
    div("setting", h("span", {}, "Copy notes as"), div("segmented", choice("detailed", "Detailed"), choice("short", "One line each"))),
    check(prefs.notify, "Notify me", "When an agent answers while this tab is in the background.", async (on) => {
      if (on && "Notification" in window && Notification.permission === "default") await Notification.requestPermission()
      const allowed = "Notification" in window && Notification.permission === "granted"
      if (on && !allowed) toast("The browser blocked notifications for this site.", { error: true })
      changeSettings({ notify: on && allowed })
      refreshPopover()
    }),
    check(prefs.compact, "Compact button", "The corner button stays small until you point at it.", (on) => changeSettings({ compact: on })),
    div("setting", h("span", {}, "Shortcut"), h("kbd", {}, shortcutLabel()), h("span", { className: "where" }, "config.shortcut in the initializer")),
    div("setting", h("button", { type: "button", onclick: () => { store("dock", { right: 16, bottom: 16 }); placeDock() } }, "Move the toolbar back to the corner")),
  ]
}
function refreshPopover() {
  if (popover && popoverTool === settingsTool) popover.replaceChildren(...renderSettings())
}
settingsTool.addEventListener("click", () => openPopover(settingsTool, renderSettings))
onSettings((prefs) => corner.classList.toggle("compact", prefs.compact))

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
  current = null
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

let current: Element | null = null
function highlight(element: Element) {
  clearHover()
  current = element
  hoverBoxes = box(documentRect(element), mode === "edit" ? "hover-edit" : "", label(element))
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

// Focus in one of the page's own fields: its keys (arrows, Enter, Cmd+C) belong to the field.
function typingInPage() {
  const active = document.activeElement
  return active instanceof HTMLElement && !isUi(active) && (active.matches("input, textarea, select") || active.isContentEditable)
}

function keyboardSelect(event: KeyboardEvent): boolean {
  if (mode !== "inspect" || !current || menu || isEditing() || activeInShadow()?.matches("textarea, input, [contenteditable]") || typingInPage()) return false
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

// Moving a note: the next click in select mode picks the element it's about.
let moving: Note | null = null
setMoveHandler((note) => {
  moving = note
  toggleSidebar(false)
  setMode("inspect")
  syncButtons()
  toast("Click the element this note is about. Esc cancels.", { timeout: 8000 })
})

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
  const list = element.closest(`ul[${MARKDOWN}], ol[${MARKDOWN}]`)
  menu = panel(rect, "menu",
    h("h3", {}, label(element)[0], h("span", { className: "where" }, label(element)[1])),
    item("copy", "Copy reference", async () => { await copy(reference(element)); toast("Copied reference") }, "C"),
    item("pad", selectedText ? "Note on selected text" : "Add note", () => noteForm(rect, targetsFor(element, selectedText)), "N"),
    kind ? item(kind === "attributes" ? "tag" : "pen", kind === "attributes" ? "Edit attributes" : "Edit text", () => edit(element, kind), "E") : null,
    kind && kind !== "attributes" && editKind(element) !== "attributes" && hasAttributes(element) ? item("tag", "Edit attributes", () => edit(element, "attributes")) : null,
    list && list !== element ? item("pen", "Edit the whole list", () => edit(list, "markdown"), "L") : null,
    undoable ? item("undo", undoable.label, () => undo(element), "U") : null,
    item("code", "Open in editor", () => openInEditor(element), "O"))
  menu.dataset.tensakuMenu = ""
  menu.addEventListener("keydown", (event) => event.stopPropagation())
  ;(menu.querySelector("button") as HTMLElement | null)?.focus()
  menuKeys = (event: KeyboardEvent) => {
    if (!menu) return
    if (!"cneluo".includes(event.key.toLowerCase()) || event.key.length !== 1 || event.metaKey || event.ctrlKey || event.altKey) return
    const all = Array.from(menu.querySelectorAll("button"))
    const match = all.find((button) => button.querySelector("kbd")?.textContent === event.key.toUpperCase())
    if (match) { event.preventDefault(); match.click() }
  }
  api("POST", "/selection", { url: location.pathname, targets: targetsFor(element, selectedText), text: visibleText(element, 300) }).catch(() => {})
}
let menuKeys: ((event: KeyboardEvent) => void) | null = null

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

function hasAttributes(element: Element) {
  return ["alt", "title", "placeholder", "aria-label"].some((name) => element.hasAttribute(name))
}

// Page events -----------------------------------------------------------------------------------

function pageTarget(event: Event): Element | null {
  const target = event.composedPath()[0] as Node
  if (isUi(target as Element) || (target instanceof Node && isUi(target.parentElement))) return null
  return sourceElement(target)
}

onDocument("mousemove", (event) => {
  if (drag) return updateDrag(event)
  if (mode === "off" || menu || isEditing()) return
  const element = pageTarget(event)
  if (!element) return clearHover()
  if (mode === "edit" && !editKind(element)) return clearHover()
  highlight(element)
}, true)

onDocument("mousedown", (event) => {
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

onDocument("mouseup", (event) => {
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

onDocument("click", (event) => {
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
  if (moving) {
    const note = moving
    moving = null
    moveNote(note, element).catch((error) => toast((error as Error).message, { error: true }))
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

onDocument("keydown", (event) => {
  if (matchesShortcut(event)) {
    event.preventDefault()
    setMode(mode === "off" ? "inspect" : "off")
    return
  }
  if (menu && menuKeys) menuKeys(event)
  if (keyboardSelect(event)) return
  if (pickBar && !isEditing() && !activeInShadow()?.matches("textarea")) {
    if (event.key.toLowerCase() === "n" && !event.metaKey && !event.ctrlKey && !event.altKey) { event.preventDefault(); notePicked(); return }
    if (event.key === "Escape") { clearPicked(); return }
  }
  if (event.key === "Escape") {
    if (popover) { closePopover(); return }
    if (moving) { moving = null; toast("Move cancelled"); return }
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
onWindow("resize", () => { placeDock(); scheduleRedraw() })

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
onDocument("turbo:load", pageChanged)
onDocument("turbo:frame-load", scheduleRedraw)
onWindow("popstate", pageChanged)
// A save can change what a template's elements contain.
pending.push(() => onRefresh(() => { templateText.clear(); scheduleRedraw(); loadNotes() }))
// Layout shifts (images loading, content changing) move elements; pins follow every second.
pending.push(() => setInterval(() => { if (location.pathname !== path) pageChanged(); else drawPins() }, 1000))
// Scrolling inside a container (an app shell's <main> with overflow) moves elements without a resize.
// Scrolling the page itself doesn't: boxes and pins are in page coordinates.
onDocument("scroll", (event) => {
  if (event.target !== document && !isUi(event.target as Element)) scheduleRedraw()
}, { capture: true, passive: true })

// Boot ------------------------------------------------------------------------------------------

function boot() {
  if (window.__tensaku) return
  window.__tensaku = true
  pending.forEach((add) => add())
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
