// The dock: the corner button, which can be dragged anywhere, and the toolbar that unrolls out of it.
// Each tool is a drawing from the pencil case, in the colour it marks the page with.

import { renderAgents } from "./agents-popover"
import { renderHistory } from "./history-popover"
import { logo, icon, type IconName } from "./icons"
import { mode, onMode, setMode } from "./mode"
import { setAgentsHandler } from "./note-card"
import { type Agent, agentLabel, currentNotes, deleteNotes, onAgents, onCount } from "./notes"
import { sidebarOpen, toggleSidebar } from "./notes-panel"
import { togglePause } from "./pause"
import { setPinsHidden } from "./pins"
import { closePopover, popoverOpen, redrawPopover, togglePopover } from "./popover"
import { onSettings } from "./settings"
import { setSettingsHooks, settingsOpen, toggleSettings } from "./settings-panel"
import { keysLabel, shortcutFor, type ShortcutTool } from "./shortcuts"
import { div, fixed, h, storage, store, toast } from "./ui"

export const INK = { highlighter: "#ffe14d", pen: "#e0344f", pad: "#fff1a1" }

const count = h("span", { className: "count", hidden: true })
const corner = h("button", { className: "corner", type: "button", title: "Tensaku", "aria-label": "Tensaku", "aria-expanded": "false" }, logo(), count)

function tool(name: IconName, ink: string, text: string) {
  const tip = h("span", { className: "tip", "aria-hidden": "true" }, text)
  const button = h("button", { type: "button", className: "tool", "aria-pressed": "false", "aria-label": text }, icon(name, ink), tip)
  button.style.setProperty("--ink-color", ink)
  return button
}
function action(name: IconName, text: string) {
  return h("button", { type: "button", className: "tool", "aria-label": text }, icon(name), h("span", { className: "tip", "aria-hidden": "true" }, text))
}
function setTip(button: HTMLElement, text: string) {
  button.setAttribute("aria-label", text)
  button.querySelector(".tip")!.firstChild!.textContent = text
}
const setIcon = (button: HTMLElement, name: IconName, ink?: string) => button.replaceChild(icon(name, ink), button.querySelector("svg")!)

const selectTool = tool("highlighter", INK.highlighter, "Select")
const editTool = tool("pen", INK.pen, "Edit")
const notesTool = tool("pad", INK.pad, "Notes")
const notesBadge = h("span", { className: "badge", hidden: true })
notesTool.append(notesBadge)
const pinsTool = action("eye", "Hide pins")
const pauseTool = action("pause", "Pause animations")
const clearTool = action("trash", "Delete this page's notes")
const historyTool = action("history", "Edit history")
const settingsTool = action("sliders", "Settings")
// The agents with `tensaku mcp` running: a grey plane with none, the plane in ink while one is
// connected, flying in green while one listens. A count when there is more than one.
const agentsTool = action("plane", "No agent connected")
agentsTool.classList.add("agents")
const agentsBadge = h("span", { className: "badge", hidden: true })
agentsTool.append(agentsBadge)

const tools = div("tools", selectTool, editTool, div("sep"), notesTool, agentsTool, pinsTool, clearTool, div("sep"), pauseTool, historyTool, settingsTool)
const toolbar = div("toolbar", tools)
// CSS can't animate to a content width.
new ResizeObserver(() => toolbar.style.setProperty("--tools-width", `${tools.offsetWidth}px`)).observe(tools)
const dock = div("dock", toolbar, corner)
fixed.append(dock)

// The button each shortcut presses. A tooltip shows the tool's shortcut, if it has one.
const shortcutButtons: Record<ShortcutTool, HTMLElement> = {
  select: selectTool, edit: editTool, notes: notesTool, agents: agentsTool, pins: pinsTool,
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

export function pressShortcut(name: ShortcutTool) {
  setToolbar(true)
  shortcutButtons[name].click()
}

// Opening and placing ----------------------------------------------------------------------------

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

// The CSS sizes the toolbar on a phone from --dock-right, the room right of the dock.
function moveDock(right: number, bottom: number) {
  dock.style.right = `${right}px`
  dock.style.bottom = `${bottom}px`
  dock.style.setProperty("--dock-right", `${right}px`)
}

export function placeDock() {
  const position = storage<{ right: number; bottom: number }>("dock", { right: 16, bottom: 16 })
  moveDock(Math.min(Math.max(position.right, 4), innerWidth - 52), Math.min(Math.max(position.bottom, 4), innerHeight - 52))
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
    moveDock(start.right - dx, start.bottom - dy)
  }
  // A cancelled pointer (the browser took over the touch) ends the drag like a release.
  const up = () => {
    corner.removeEventListener("pointermove", move)
    corner.removeEventListener("pointerup", up)
    corner.removeEventListener("pointercancel", up)
    corner.style.cursor = ""
    if (dragged) store("dock", { right: parseFloat(dock.style.right), bottom: parseFloat(dock.style.bottom) })
  }
  corner.addEventListener("pointermove", move)
  corner.addEventListener("pointerup", up)
  corner.addEventListener("pointercancel", up)
})
corner.addEventListener("click", () => {
  if (dragged) return
  setToolbar(!toolbarOpen())
  if (toolbarOpen()) return
  toggleSidebar(false)
  toggleSettings(false)
  setMode("off")
})

// Escape folds the toolbar away once nothing else is open (index.ts). Returns whether it was open.
export function closeToolbar(): boolean {
  if (!toolbarOpen()) return false
  setToolbar(false)
  return true
}

// Modes and panels -------------------------------------------------------------------------------

function syncButtons() {
  selectTool.setAttribute("aria-pressed", String(mode() === "inspect"))
  editTool.setAttribute("aria-pressed", String(mode() === "edit"))
  notesTool.setAttribute("aria-pressed", String(sidebarOpen()))
  settingsTool.setAttribute("aria-pressed", String(settingsOpen()))
  corner.classList.toggle("active", mode() !== "off")
}
onMode((next) => {
  if (next !== "off") setToolbar(true)
  syncButtons()
})

// Closes the settings panel or the notes panel, for Escape. Returns whether one was open.
export function closeSidePanel(): boolean {
  if (settingsOpen()) { toggleSettings(false); return true }
  if (!sidebarOpen()) return false
  toggleSidebar(false)
  syncButtons()
  return true
}

selectTool.addEventListener("click", () => setMode(mode() === "inspect" ? "off" : "inspect"))
editTool.addEventListener("click", () => setMode(mode() === "edit" ? "off" : "edit"))
notesTool.addEventListener("click", () => { toggleSettings(false); toggleSidebar(); syncButtons() })

onCount((n) => {
  count.hidden = n === 0
  count.textContent = String(n)
  notesBadge.hidden = n === 0
  notesBadge.textContent = String(n)
  setTip(notesTool, n ? `Notes (${n})` : "Notes")
})

// The settings panel takes the notes panel's place.
setSettingsHooks({
  toggled: syncButtons,
  moveDockHome: () => { store("dock", { right: 16, bottom: 16 }); placeDock() },
})
settingsTool.addEventListener("click", () => { closePopover(); if (!settingsOpen()) toggleSidebar(false); toggleSettings() })

historyTool.addEventListener("click", () => togglePopover(historyTool, dock, renderHistory))

// Pins, pause and clear --------------------------------------------------------------------------

let pinsHidden = storage("pinsHidden", false)
export function syncPins() {
  setPinsHidden(pinsHidden)
  pinsTool.setAttribute("aria-pressed", String(pinsHidden))
  setIcon(pinsTool, pinsHidden ? "eye-off" : "eye")
  setTip(pinsTool, pinsHidden ? "Show pins" : "Hide pins")
}
pinsTool.addEventListener("click", () => { pinsHidden = !pinsHidden; store("pinsHidden", pinsHidden); syncPins() })

pauseTool.addEventListener("click", () => {
  const paused = togglePause()
  pauseTool.setAttribute("aria-pressed", String(paused))
  setIcon(pauseTool, paused ? "play" : "pause")
  setTip(pauseTool, paused ? "Resume animations" : "Pause animations")
})

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

// Agents -----------------------------------------------------------------------------------------

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
  setIcon(agentsTool, listening.length ? "plane-flying" : "plane", listening.length ? "#2fa872" : undefined)
  agentsBadge.hidden = agents.length < 2
  agentsBadge.textContent = String(agents.length)
  setTip(agentsTool, listening.length ? `${names(listening)} listening` : agents.length ? `${names(agents)} connected` : "No agent connected")
  redrawPopover(agentsTool)
})

agentsTool.addEventListener("click", () => togglePopover(agentsTool, dock, renderAgents))
setAgentsHandler(() => { setToolbar(true); if (!popoverOpen(agentsTool)) togglePopover(agentsTool, dock, renderAgents) })
