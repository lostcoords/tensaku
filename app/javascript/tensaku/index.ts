// Tensaku's overlay. Injected by the middleware in development; reads the stamps producers wrote into
// the page and talks to the endpoints under /__tensaku. This file routes the page's pointer and key
// events to the dock (dock.ts), select mode (inspect.ts), the editor and the note form, and keeps
// pins and boxes in place.

import { isApple } from "./api"
import "./announce"
import { closeSidePanel, closeToolbar, INK, placeDock, pressShortcut, syncPins } from "./dock"
import { documentRect, editKind, isUi, sourceElement, templateText, typingInPage } from "./dom"
import { closeEditor, edit, isEditing } from "./editor"
import { canRedo, canUndo, redo, undo } from "./history"
import { cursor } from "./icons"
import { clearHover, clearPicked, closeMenu, drawPicked, hasPicked, highlight, menuKey, menuOpen, openMenu, pickKey, selectKey, sendSelection, togglePicked } from "./inspect"
import { watch as watchMarkers } from "./markers"
import { mode, onMode, setMode } from "./mode"
import { closeNote, noteForm } from "./note-card"
import { elementsInArea, targetsFor } from "./note-targets"
import { load as loadNotes, poll as pollNotes } from "./notes"
import { drawOutlines } from "./outlines"
import { drawPins } from "./pins"
import { closeOutside, closePopover, popoverOpen } from "./popover"
import { onRefresh } from "./refresh"
import { hasCommandModifier, toolForEvent } from "./shortcuts"
import { activeInShadow, box, div, layer, mount } from "./ui"

declare global {
  interface Window { __tensaku?: boolean }
}

// Listeners on the page (document and window) and timers are only added by boot(), after its guard, so
// a second copy of this script on the page adds nothing. Listeners on the overlay's own elements stay
// in their modules: a second copy's elements are never mounted.
const pending: (() => void)[] = []
function onDocument<K extends keyof DocumentEventMap>(type: K, listener: (event: DocumentEventMap[K]) => void, options?: boolean | AddEventListenerOptions): void
function onDocument(type: string, listener: (event: Event) => void, options?: boolean | AddEventListenerOptions): void
function onDocument(type: string, listener: (event: any) => void, options?: boolean | AddEventListenerOptions) {
  pending.push(() => document.addEventListener(type, listener, options))
}
function onWindow<K extends keyof WindowEventMap>(type: K, listener: (event: WindowEventMap[K]) => void) {
  pending.push(() => addEventListener(type, listener))
}

onMode((next) => {
  if (next !== "inspect" && hasPicked()) clearPicked()
  clearHover()
  closeMenu()
  drawOutlines()
  syncCursor()
})

function syncCursor() {
  document.documentElement.style.cursor = altHeld || mode() === "inspect" ? cursor("highlighter", INK.highlighter) : mode() === "edit" ? cursor("pen", INK.pen) : ""
}

// Holding Alt/Option previews what Alt-click would pick: the select cursor and highlight, in any mode,
// until the key is released. Not while typing, where Option types characters and moves by word.
let altHeld = false
let pointer: { x: number; y: number } | null = null
const altPreviews = (event: KeyboardEvent | MouseEvent) =>
  event.altKey && !event.metaKey && !event.ctrlKey && !isEditing() && !typingInPage() && !activeInShadow()?.matches("textarea, input")

function setAltHeld(held: boolean) {
  if (held === altHeld) return
  altHeld = held
  syncCursor()
  if (!held) { if (mode() !== "inspect") clearHover(); return }
  const under = pointer && !menuOpen() ? document.elementFromPoint(pointer.x, pointer.y) : null
  const element = under && !isUi(under) ? sourceElement(under) : null
  if (element) highlight(element)
}

// Pointer ----------------------------------------------------------------------------------------

// A drag in select mode, or with Alt in any mode, draws an area for a note.
let drag: { x: number; y: number; area: HTMLElement | null } | null = null
let suppressClick = false

function pageTarget(event: Event): Element | null {
  const target = event.composedPath()[0] as Node
  if (isUi(target as Element) || (target instanceof Node && isUi(target.parentElement))) return null
  return sourceElement(target)
}

onDocument("mousemove", (event) => {
  if (drag) return updateDrag(event)
  pointer = { x: event.clientX, y: event.clientY }
  setAltHeld(altPreviews(event))
  if ((mode() === "off" && !altHeld) || menuOpen() || isEditing()) return
  const element = pageTarget(event)
  if (!element) return clearHover()
  const editing = mode() === "edit" && !altHeld
  if (editing && !editKind(element)) return clearHover()
  highlight(element, editing ? "hover-edit" : "")
}, true)

onDocument("mousedown", (event) => {
  if (event.button !== 0 || isUi(event.target as Element)) return
  // Alt keeps any selected text for the menu and note form, and Alt-drag draws an area, in any mode.
  const altDrag = event.altKey
  if (altDrag) event.preventDefault()
  if ((mode() !== "inspect" && !altDrag) || menuOpen() || isEditing()) return
  // Shift would extend the text selection; it picks elements in select mode and writes a note with Alt.
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
  }, undefined, new DOMRect(event.pageX, event.pageY, 0, 0))
  sendSelection(targets, "")
}, true)

onDocument("click", (event) => {
  if (suppressClick) { suppressClick = false; event.preventDefault(); event.stopPropagation(); return }
  if (isUi(event.target as Element)) return
  const element = pageTarget(event)
  const at = new DOMRect(event.pageX, event.pageY, 0, 0)
  const selectedIn = (within: Element) => {
    const selection = getSelection()?.toString().trim()
    return selection && within.contains(getSelection()!.anchorNode) ? selection : undefined
  }

  // Alt/Option+Shift-click writes a note right away, and Alt/Option-click opens the menu, in any mode.
  if (event.altKey && element) {
    event.preventDefault()
    event.stopImmediatePropagation()
    closeMenu()
    if (event.shiftKey) noteForm(documentRect(element), targetsFor(element, selectedIn(element)), {}, undefined, undefined, at)
    else openMenu(element, selectedIn(element), at)
    return
  }
  if (mode() === "off" && !menuOpen()) return
  event.preventDefault()
  event.stopImmediatePropagation()
  if (menuOpen() || isEditing()) { closeMenu(); return }
  if (!element) return

  if (mode() === "edit") {
    const kind = editKind(element)
    if (kind) edit(element, kind)
    return
  }
  if (event.shiftKey) { togglePicked(element); return }
  if (hasPicked()) clearPicked()
  openMenu(element, selectedIn(element), at)
}, true)

onDocument("pointerdown", closeOutside, true)

// Keys -------------------------------------------------------------------------------------------

// Cmd/Ctrl+Z undoes the latest save, Cmd/Ctrl+Shift+Z or Ctrl+Y redoes (UNDO_KEYS), unless something
// is being typed in (the page's own fields and Tensaku's editor keep their own undo) or there is
// nothing to undo.
function undoKeys(event: KeyboardEvent): boolean {
  if (!(isApple ? event.metaKey : event.ctrlKey) || event.altKey || isEditing() || typingInPage() || activeInShadow()?.matches("textarea, input, [contenteditable]")) return false
  const key = event.key.toLowerCase()
  const wantsRedo = (key === "z" && event.shiftKey) || (!isApple && key === "y")
  const wantsUndo = key === "z" && !event.shiftKey
  if (wantsUndo && canUndo()) { event.preventDefault(); undo(); return true }
  if (wantsRedo && canRedo()) { event.preventDefault(); redo(); return true }
  return false
}

onDocument("keydown", (event) => {
  if (event.key === "Alt") setAltHeld(altPreviews(event))
  const shortcut = hasCommandModifier(event) ? toolForEvent(event) : null
  if (shortcut) {
    event.preventDefault()
    pressShortcut(shortcut)
    return
  }
  if (undoKeys(event)) return
  menuKey(event)
  if (selectKey(event)) return
  if (pickKey(event)) return
  if (event.key === "Escape") escape()
}, true)

// Each Escape closes one thing, the innermost first: it leaves a field in Tensaku's panels (the note
// form and the comment editor also close on it), then closes the popover, the element menu, the note
// opened from a pin and the side panel, turns select or edit mode off, and last folds the toolbar
// away. The editor closes itself, and a field of the page keeps its own Escape.
function escape() {
  if (isEditing() || typingInPage()) return
  const field = activeInShadow()
  if (field?.matches("textarea, input, [contenteditable]")) { (field as HTMLElement).blur(); return }
  if (popoverOpen()) closePopover()
  else if (menuOpen()) closeMenu()
  else if (closeNote() || closeSidePanel()) return
  else if (mode() !== "off") setMode("off")
  else closeToolbar()
}
onDocument("keyup", (event) => { if (event.key === "Alt") setAltHeld(false) }, true)
onWindow("blur", () => setAltHeld(false))

// Keeping pins and boxes in place ----------------------------------------------------------------

let redraw = 0
function scheduleRedraw() {
  cancelAnimationFrame(redraw)
  redraw = requestAnimationFrame(() => { drawPins(); drawOutlines(); if (hasPicked()) drawPicked() })
}
onWindow("resize", () => { placeDock(); scheduleRedraw() })

let path = location.pathname
function pageChanged() {
  path = location.pathname
  closeMenu()
  clearPicked()
  closeEditor()
  clearHover()
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

// Boot -------------------------------------------------------------------------------------------

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
