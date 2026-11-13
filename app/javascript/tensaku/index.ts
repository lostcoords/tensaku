// Tensaku's overlay. Injected by the middleware in development; reads the stamps producers wrote into
// the page and talks to the endpoints under /__tensaku.

import { api, isApple, meta, query } from "./api"
import { contextOf, documentRect, editKind, hasOwnText, isUi, MARKDOWN, nearestStamp, sourceElement, STAMP, stampOf, tagLabel, templateText, translationOf, visibleText, copiesOf } from "./dom"
import { canRedo, canUndo, closeEditor, edit, editHistory, isEditing, redo, undo, undoFor } from "./editor"
import { watch as watchMarkers } from "./markers"
import { type Agent, agentLabel, currentAgents, currentNotes, deleteNotes, drawPins, elementsInArea, load as loadNotes, noteForm, onAgents, onCount, setAgentsHandler, poll as pollNotes, setPinsHidden, sidebarOpen, targetsFor, toggleSidebar } from "./notes"
import { onSettings } from "./settings"
import { setSettingsHooks, settingsOpen, toggleSettings } from "./settings-panel"
import { hasCommandModifier, keysLabel, shortcutFor, type ShortcutTool, toolForEvent } from "./shortcuts"
import { onRefresh } from "./refresh"
import { logo, cursor, icon, type IconName } from "./icons"
import { activeInShadow, box, copy, div, fixed, h, layer, mount, panel, storage, store, toast } from "./ui"

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
const corner = h("button", { className: "corner", type: "button", title: "Tensaku", "aria-label": "Tensaku", "aria-expanded": "false" }, logo(), count)
// Each tool is a drawing from the pencil case, in the colour it marks the page with.
const INK = { highlighter: "#ffe14d", pen: "#e0344f", pad: "#fff1a1" }
function tool(name: IconName, ink: string, text: string) {
  const tip = h("span", { className: "tip", "aria-hidden": "true" }, text)
  const button = h("button", { type: "button", className: "tool", "aria-pressed": "false", "aria-label": text }, icon(name, ink), tip)
  button.style.setProperty("--ink-color", ink)
  return button
}
const buttons = {
  inspect: tool("highlighter", INK.highlighter, "Select"),
  edit: tool("pen", INK.pen, "Edit"),
  notes: tool("pad", INK.pad, "Notes"),
}
const notesBadge = h("span", { className: "badge", hidden: true })
buttons.notes.append(notesBadge)
function action(name: IconName, text: string) {
  return h("button", { type: "button", className: "tool", "aria-label": text }, icon(name), h("span", { className: "tip", "aria-hidden": "true" }, text))
}
const setTip = (button: HTMLElement, text: string) => {
  button.setAttribute("aria-label", text)
  button.querySelector(".tip")!.firstChild!.textContent = text
}
const pinsTool = action("eye", "Hide pins")
const pauseTool = action("pause", "Pause animations")
const clearTool = action("trash", "Delete this page's notes")
const historyTool = action("history", "Edit history")
const settingsTool = action("sliders", "Settings")
// The agents with `tensaku mcp` running: a dot while one is connected, pulsing while one listens.
// The agents with `tensaku mcp` running: a grey plane with none, the plane in ink while one is
// connected, flying in green while one listens. A count when there is more than one.
const agentsTool = action("plane", "No agent connected")
agentsTool.classList.add("agents")
const agentsBadge = h("span", { className: "badge", hidden: true })
agentsTool.append(agentsBadge)
const tools = div("tools", buttons.inspect, buttons.edit, div("sep"), buttons.notes, agentsTool, pinsTool, clearTool, div("sep"), pauseTool, historyTool, settingsTool)
const toolbar = div("toolbar", tools)
// The button each shortcut presses. A tooltip shows the tool's shortcut, if it has one.
const shortcutButtons: Record<ShortcutTool, HTMLElement> = {
  select: buttons.inspect, edit: buttons.edit, notes: buttons.notes, agents: agentsTool, pins: pinsTool,
  clear: clearTool, pause: pauseTool, history: historyTool, settings: settingsTool,
}
onSettings(() => {
  for (const [name, button] of Object.entries(shortcutButtons) as [ShortcutTool, HTMLElement][]) {
    const keys = shortcutFor(name)
    const tip = button.querySelector(".tip")!
    tip.querySelector("kbd")?.remove()
    if (keys) tip.append(h("kbd", {}, keysLabel(keys)))
  }
})
// CSS can't animate to a content width.
new ResizeObserver(() => toolbar.style.setProperty("--tools-width", `${tools.offsetWidth}px`)).observe(tools)
const dock = div("dock", toolbar, corner)
fixed.append(dock)

// The dock is one pill with the corner button at its end, and the tools unroll out of it. They are
// clipped while they do, then "settled" lets tooltips and badges out of the pill.
const toolbarOpen = () => dock.classList.contains("open")
let settling = 0
function setToolbar(open: boolean) {
  if (open === toolbarOpen()) return
  dock.classList.toggle("open", open)
  corner.setAttribute("aria-expanded", String(open))
  clearTimeout(settling)
  dock.classList.remove("settled")
  if (open) settling = window.setTimeout(() => dock.classList.add("settled"), 280)
}

function placeDock() {
  const position = storage<{ right: number; bottom: number }>("dock", { right: 16, bottom: 16 })
  dock.style.right = `${Math.min(Math.max(position.right, 4), innerWidth - 52)}px`
  dock.style.bottom = `${Math.min(Math.max(position.bottom, 4), innerHeight - 52)}px`
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
  setToolbar(!toolbarOpen())
  if (toolbarOpen()) return
  toggleSidebar(false)
  toggleSettings(false)
  setMode("off")
})
buttons.inspect.addEventListener("click", () => setMode(mode === "inspect" ? "off" : "inspect"))
buttons.edit.addEventListener("click", () => setMode(mode === "edit" ? "off" : "edit"))
buttons.notes.addEventListener("click", () => { toggleSettings(false); toggleSidebar(); syncButtons() })
let pinsHidden = storage("pinsHidden", false)
function syncPins() {
  setPinsHidden(pinsHidden)
  pinsTool.setAttribute("aria-pressed", String(pinsHidden))
  pinsTool.replaceChild(icon(pinsHidden ? "eye-off" : "eye"), pinsTool.querySelector("svg")!)
  setTip(pinsTool, pinsHidden ? "Show pins" : "Hide pins")
}
pinsTool.addEventListener("click", () => { pinsHidden = !pinsHidden; store("pinsHidden", pinsHidden); syncPins() })

// Pausing stops the page's CSS animations and transitions, Web Animations and playing media, so an
// element can be noted mid-animation. Timers and requestAnimationFrame loops keep running.
let paused: { animations: Animation[]; media: HTMLMediaElement[]; style: HTMLStyleElement } | null = null
function togglePause() {
  if (paused) {
    paused.style.remove()
    paused.animations.forEach((animation) => { try { animation.play() } catch { /* finished or removed meanwhile */ } })
    paused.media.forEach((media) => media.play().catch(() => {}))
    paused = null
  } else {
    const animations = document.getAnimations().filter((animation) => {
      const target = (animation.effect as KeyframeEffect | null)?.target
      return animation.playState === "running" && !(target && isUi(target))
    })
    animations.forEach((animation) => animation.pause())
    const media = Array.from(document.querySelectorAll<HTMLMediaElement>("video, audio")).filter((element) => !element.paused)
    media.forEach((element) => element.pause())
    const style = document.createElement("style")
    style.setAttribute("data-tensaku-pause", "")
    style.textContent = "*, *::before, *::after { animation-play-state: paused !important; transition: none !important; }"
    document.head.append(style)
    paused = { animations, media, style }
  }
  pauseTool.setAttribute("aria-pressed", String(Boolean(paused)))
  pauseTool.replaceChild(icon(paused ? "play" : "pause"), pauseTool.querySelector("svg")!)
  setTip(pauseTool, paused ? "Resume animations" : "Pause animations")
}
pauseTool.addEventListener("click", togglePause)

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
    await deleteNotes(currentNotes())
    toast(`Deleted ${total} ${total === 1 ? "note" : "notes"}`)
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

const names = (list: Agent[]) => list.map(agentLabel).join(", ")
// Every poll reports the agents; the button and an open popover change only when they did, so a
// redraw never swallows a click in the popover.
let agentsSignature = "[]"
onAgents((agents) => {
  const signature = JSON.stringify(agents)
  if (signature === agentsSignature) return
  agentsSignature = signature
  const listening = agents.filter((agent) => agent.listening)
  agentsTool.classList.toggle("connected", agents.length > 0)
  agentsTool.classList.toggle("listening", listening.length > 0)
  agentsTool.replaceChild(listening.length ? icon("plane-flying", "#2fa872") : icon("plane"), agentsTool.querySelector("svg")!)
  agentsBadge.hidden = agents.length < 2
  agentsBadge.textContent = String(agents.length)
  setTip(agentsTool, listening.length ? `${names(listening)} listening` : agents.length ? `${names(agents)} connected` : "No agent connected")
  if (popover && popoverTool === agentsTool) popover.replaceChildren(...renderAgents())
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
  // In the top layer after the notes panel, so the panel never covers it, placed above the dock.
  const rect = dock.getBoundingClientRect()
  popover.style.right = `${Math.max(12, innerWidth - rect.right)}px`
  popover.style.bottom = `${innerHeight - rect.top + 12}px`
  fixed.append(popover)
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
// The saves in this tab, newest first, with Undo on each, and the undone ones below, the latest with
// Redo. Undo and redo also work from the keyboard (UNDO_KEYS).
function renderHistory(): Node[] {
  const { done, undone } = editHistory()
  const row = (entry: (typeof done)[number], action: Node) => div(`entry${undone.includes(entry) ? " undone" : ""}`,
    div("what", h("span", {}, entry.label), h("span", { className: "where" }, `${entry.file ?? ""} · ${ago(new Date(entry.at))}`)), action)
  const button = (text: string, run: () => Promise<unknown>) => h("button", { type: "button", onclick: async () => { await run(); closePopover() } }, text)
  return [
    h("h3", {}, "Edit history", h("span", { className: "where" }, `Saves in this tab. ${UNDO_KEYS} undo and redo.`)),
    ...(done.length || undone.length ? [
      ...done.map((entry) => row(entry, button("Undo", () => undo(entry)))),
      ...undone.map((entry, i) => row(entry, i === 0 ? button("Redo", () => redo(entry)) : h("span", { className: "where" }, "undone"))),
    ] : [div("empty", "No edits yet.")]),
  ]
}
historyTool.addEventListener("click", () => openPopover(historyTool, renderHistory))

// What an agent can be asked, in its own chat. Tensaku can't start an agent's turn, so listening is
// something the person asks for.
const PROMPTS = { watch: "Watch my Tensaku notes", once: "Do my Tensaku notes", install: "bin/rails generate tensaku:install" }
function copyRow(text: string, done: string) {
  return div("command", h("code", {}, text),
    h("button", { type: "button", className: "icon-button", title: "Copy", "aria-label": `Copy ${text}`, onclick: async () => { await copy(text); toast(done) } }, icon("copy")))
}
// What the agent last did, from its last tool call: "resolved xz5b 1 min ago".
const DID: Record<string, string> = { start_note: "started", resolve_note: "resolved", decline_note: "declined", ask_question: "asked on", reply_to_note: "replied on", get_note: "read", list_notes: "listed the notes", watch_notes: "checked for notes", current_selection: "read the selection" }
function lastAction(agent: Agent) {
  if (agent.working.length) return agent.working.map((note) => h("a", { className: "doing", href: note.url, title: `“${note.comment}”` }, `Working on ${note.id}: “${note.comment}”`))
  const last = agent.last
  const did = last ? `${DID[last.tool] ?? last.tool}${last.note ? ` ${last.note}` : ""} ${ago(new Date(last.at))}` : null
  const text = agent.listening ? `Waiting for your notes${did ? ` · ${did}` : ""}` : did ? `Last ${did}` : "No calls yet"
  return [h("span", { className: "doing" }, text)]
}
// One agent: its name and handle, the folder it runs in, and what it did last.
function agentRow(agent: Agent) {
  return div(`agent${agent.listening ? " listening" : ""}${agent.working.length ? " working" : ""}`,
    div("who", h("strong", {}, agentLabel(agent)), h("span", { className: "where" }, agent.folder ?? "")),
    ...lastAction(agent))
}
let idleOpen = false
function renderAgents(): Node[] {
  const agents = currentAgents()
  const listening = agents.filter((agent) => agent.listening)
  const idle = agents.filter((agent) => !agent.listening)
  const ask = [
    h("p", {}, "Ask an agent to listen, and each note you save reaches it as you write it:"),
    copyRow(PROMPTS.watch, "Copied. Paste it into your agent."),
    h("p", {}, "Or have it work through the open notes once:"),
    copyRow(PROMPTS.once, "Copied. Paste it into your agent."),
  ]
  // Listeners first. The rest, connected but not listening, are one line that expands, unless they are all there is.
  const rest = listening.length && idle.length
    ? [h("button", { type: "button", className: "idle-toggle", "aria-expanded": String(idleOpen), onclick: () => { idleOpen = !idleOpen; popover?.replaceChildren(...renderAgents()) } },
        `${idle.length} more connected, not listening`), ...(idleOpen ? idle.map(agentRow) : [])]
    : idle.map(agentRow)
  return [
    h("h3", {}, "Agents", h("span", { className: "where" }, "Coding agents running tensaku mcp in this app. A note belongs to the agent that takes it.")),
    ...(agents.length
      ? [...listening.map(agentRow), ...rest]
      : [div("empty", "No agent connected."),
          div("connect", h("p", {}, "An agent gets Tensaku's tools from tensaku mcp in its project config. This adds it for Claude Code, Codex, Cursor, Gemini CLI and OpenCode:"),
            copyRow(PROMPTS.install, "Copied. Run it in the app, then restart your agent."))]),
    ...(listening.length ? [] : [div("connect", ...ask)]),
  ]
}
agentsTool.addEventListener("click", () => openPopover(agentsTool, renderAgents))
setAgentsHandler(() => { setToolbar(true); if (popoverTool !== agentsTool) openPopover(agentsTool, renderAgents) })

// The settings panel takes the notes panel's place.
setSettingsHooks({
  toggled: () => syncButtons(),
  moveDockHome: () => { store("dock", { right: 16, bottom: 16 }); placeDock() },
})
settingsTool.addEventListener("click", () => { closePopover(); if (!settingsOpen()) toggleSidebar(false); toggleSettings() })


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
  settingsTool.setAttribute("aria-pressed", String(settingsOpen()))
  corner.classList.toggle("active", mode !== "off")
}

function setMode(next: Mode) {
  mode = next
  if (next !== "inspect" && picked.length) clearPicked()
  if (next !== "off") setToolbar(true)
  clearHover()
  closeMenu()
  drawEditBoxes()
  syncCursor()
  syncButtons()
}

function syncCursor() {
  document.documentElement.style.cursor = altHeld || mode === "inspect" ? cursor("highlighter", INK.highlighter) : mode === "edit" ? cursor("pen", INK.pen) : ""
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
  if (!held) { if (mode !== "inspect") clearHover(); return }
  const under = pointer && !menu ? document.elementFromPoint(pointer.x, pointer.y) : null
  const element = under && !isUi(under) ? sourceElement(under) : null
  if (element) highlight(element)
}

// Highlights ------------------------------------------------------------------------------------

function clearHover() {
  current = null
  hoverBoxes.forEach((b) => b.remove())
  hoverBoxes = []
}

function label(element: Element): readonly [string, string] {
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
  hoverBoxes = box(documentRect(element), mode === "edit" && !altHeld ? "hover-edit" : "", label(element))
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
  if (mode === "off") clearHover()
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
    kind ? item(kind === "attributes" ? "tag" : "pen", kind === "attributes" ? "Edit attributes" : "Edit text", () => edit(element, kind), "E") : null,
    kind && kind !== "attributes" && editKind(element) !== "attributes" && hasAttributes(element) ? item("tag", "Edit attributes", () => edit(element, "attributes")) : null,
    list && list !== element ? item("pen", "Edit the whole list", () => edit(list, "markdown"), "L") : null,
    item("pad", selectedText ? "Note on selected text" : "Add note", () => noteForm(rect, targetsFor(element, selectedText)), "N"),
    item("copy", "Copy reference", async () => { await copy(reference(element)); toast("Copied reference") }, "C"),
    undoable ? item("undo", `Undo ${undoable.label}`, () => undo(undoable), "U") : null,
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
  api("POST", "/selection", { url: location.pathname, tab: TAB, targets: targetsFor(element, selectedText), text: visibleText(element, 300) }).catch(() => {})
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
  pointer = { x: event.clientX, y: event.clientY }
  setAltHeld(altPreviews(event))
  if ((mode === "off" && !altHeld) || menu || isEditing()) return
  const element = pageTarget(event)
  if (!element) return clearHover()
  if (mode === "edit" && !altHeld && !editKind(element)) return clearHover()
  highlight(element)
}, true)

onDocument("mousedown", (event) => {
  if (event.button !== 0 || isUi(event.target as Element)) return
  // Alt keeps any selected text for the menu and note form, and Alt-drag draws an area, in any mode.
  const altDrag = event.altKey
  if (altDrag) event.preventDefault()
  if ((mode !== "inspect" && !altDrag) || menu || isEditing()) return
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
  })
  api("POST", "/selection", { url: location.pathname, tab: TAB, targets, text: "" }).catch(() => {})
}, true)

onDocument("click", (event) => {
  if (suppressClick) { suppressClick = false; event.preventDefault(); event.stopPropagation(); return }
  if (isUi(event.target as Element)) return
  const element = pageTarget(event)
  const selectedIn = (within: Element) => {
    const selection = getSelection()?.toString().trim()
    return selection && within.contains(getSelection()!.anchorNode) ? selection : undefined
  }

  // Alt/Option+Shift-click writes a note right away, and Alt/Option-click opens the menu, in any mode.
  if (event.altKey && element) {
    event.preventDefault()
    event.stopImmediatePropagation()
    closeMenu()
    if (event.shiftKey) noteForm(documentRect(element), targetsFor(element, selectedIn(element)))
    else openMenu(element, selectedIn(element))
    return
  }
  if (mode === "off" && !menu) return
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
  openMenu(element, selectedIn(element))
}, true)


onDocument("keyup", (event) => { if (event.key === "Alt") setAltHeld(false) }, true)
onWindow("blur", () => setAltHeld(false))

// Cmd/Ctrl+Z undoes the latest save, Cmd/Ctrl+Shift+Z or Ctrl+Y redoes, unless something is being
// typed in (the page's own fields and Tensaku's editor keep their own undo) or there is nothing to undo.
const UNDO_KEYS = isApple ? "⌘Z and ⇧⌘Z" : "Ctrl+Z and Ctrl+Y"
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
    setToolbar(true)
    shortcutButtons[shortcut].click()
    return
  }
  if (undoKeys(event)) return
  if (menu && menuKeys) menuKeys(event)
  if (keyboardSelect(event)) return
  if (pickBar && !isEditing() && !activeInShadow()?.matches("textarea")) {
    if (event.key.toLowerCase() === "n" && !event.metaKey && !event.ctrlKey && !event.altKey) { event.preventDefault(); notePicked(); return }
    if (event.key === "Escape") { clearPicked(); return }
  }
  if (event.key === "Escape") {
    if (popover) { closePopover(); return }
    if (settingsOpen()) { toggleSettings(false); return }
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
