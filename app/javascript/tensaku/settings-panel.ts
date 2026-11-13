// The settings panel: a side panel like the notes panel, with the copy format, notifications, the
// keyboard shortcuts and the toolbar's place. Everything in it is kept in this browser.

import { icon } from "./icons"
import { changeSettings, settings } from "./settings"
import { SHORTCUT_TOOLS, type ShortcutTool, hasCommandModifier, isDefault, isModifierKey, keysLabel, keysOf, resetShortcuts, setShortcut, shortcutFor } from "./shortcuts"
import { div, fixed, h, toast } from "./ui"
import { isApple } from "./api"

let panel: HTMLElement | null = null
let recording: ShortcutTool | null = null
let hooks = { toggled: () => {}, moveDockHome: () => {} }

export const setSettingsHooks = (given: typeof hooks) => { hooks = given }
export const settingsOpen = () => Boolean(panel?.isConnected)

export function toggleSettings(force?: boolean) {
  const show = force ?? !settingsOpen()
  stopRecording()
  if (!show) { panel?.remove(); hooks.toggled(); return }
  panel ??= div("sidebar settings")
  panel.setAttribute("role", "complementary")
  panel.setAttribute("aria-label", "Tensaku settings")
  fixed.append(panel)
  render()
  hooks.toggled()
}

function render() {
  if (!panel) return
  const prefs = settings()
  const choice = (value: "detailed" | "short", text: string) =>
    h("button", { type: "button", "aria-pressed": String(prefs.copyFormat === value), onclick: () => { changeSettings({ copyFormat: value }); render() } }, text)
  const notify = h("input", { type: "checkbox", checked: prefs.notify })
  notify.addEventListener("change", async () => {
    const on = notify.checked
    if (on && "Notification" in window && Notification.permission === "default") await Notification.requestPermission()
    const allowed = "Notification" in window && Notification.permission === "granted"
    if (on && !allowed) toast("The browser blocked notifications for this site.", { error: true })
    changeSettings({ notify: on && allowed })
    render()
  })
  const customized = (Object.keys(SHORTCUT_TOOLS) as ShortcutTool[]).some((tool) => !isDefault(tool))

  panel.replaceChildren(
    h("header", {}, h("strong", {}, "Settings"), h("button", { type: "button", className: "icon-button", onclick: () => toggleSettings(false), "aria-label": "Close settings" }, icon("close"))),
    h("section", {},
      h("h4", {}, "Notes"),
      div("setting", h("span", {}, "Copy notes as"), div("segmented", choice("detailed", "Detailed"), choice("short", "One line each"))),
      h("label", { className: "check" }, notify, h("span", {}, "Notify me", h("span", { className: "where" }, "When an agent answers while this tab is in the background.")))),
    h("section", {},
      h("h4", {}, "Keyboard shortcuts", customized ? h("button", { type: "button", className: "link", onclick: () => { resetShortcuts(); render() } }, "Reset all") : null),
      h("p", { className: "where" }, "Click a shortcut and press the new keys, with Alt, Ctrl or Cmd. Escape cancels."),
      ...(Object.entries(SHORTCUT_TOOLS) as [ShortcutTool, string][]).map(([tool, name]) => shortcutRow(tool, name)),
      h("h5", {}, "Always on"),
      ...fixedShortcuts().map(([keys, what]) => div("shortcut always", h("span", {}, what), h("kbd", {}, keys)))),
    h("section", {},
      h("h4", {}, "Toolbar"),
      div("setting", h("button", { type: "button", onclick: () => hooks.moveDockHome() }, "Move the toolbar back to the corner"))),
  )
}

function shortcutRow(tool: ShortcutTool, name: string) {
  const keys = shortcutFor(tool)
  const waiting = recording === tool
  const record = h("button", { type: "button", className: `keys${waiting ? " recording" : ""}`, "aria-label": `Change the shortcut for ${name}`, onclick: () => startRecording(tool) },
    waiting ? "Press keys…" : keys ? h("kbd", {}, keysLabel(keys)) : h("span", { className: "none" }, "None"))
  const clear = keys && !waiting
    ? h("button", { type: "button", className: "icon-button", "aria-label": `Remove the shortcut for ${name}`, onclick: () => { setShortcut(tool, null); render() } }, icon("close"))
    : null
  return div(`shortcut${isDefault(tool) ? "" : " changed"}`, h("span", {}, name), record, clear)
}

function startRecording(tool: ShortcutTool) {
  stopRecording()
  recording = tool
  addEventListener("keydown", onRecordKey, true)
  render()
}

function stopRecording() {
  recording = null
  removeEventListener("keydown", onRecordKey, true)
}

function onRecordKey(event: KeyboardEvent) {
  if (!recording || !settingsOpen()) { stopRecording(); return }
  if (isModifierKey(event)) return
  event.preventDefault()
  event.stopImmediatePropagation()
  const tool = recording
  stopRecording()
  if (event.key === "Escape") { render(); return }
  if (!hasCommandModifier(event)) {
    toast("Use Alt, Ctrl or Cmd with the key, so typing never triggers it.", { error: true })
    render()
    return
  }
  const keys = keysOf(event)
  const moved = setShortcut(tool, keys)
  if (moved) toast(`${keysLabel(keys)} no longer does ${SHORTCUT_TOOLS[moved]}.`)
  render()
}

// What the overlay always does with these keys, for the list under the shortcuts.
function fixedShortcuts(): [string, string][] {
  const click = (keys: string) => (isApple ? `${keys} click` : `${keys}+click`)
  const alt = isApple ? "⌥" : "Alt"
  const shift = isApple ? "⇧" : "Shift"
  return [
    [click(alt), "Menu for an element"],
    [click(isApple ? alt + shift : `${alt}+${shift}`), "Note on an element"],
    [click(shift), "Pick several elements, in select mode"],
    ["N", "Note the picked elements"],
    ["Esc", "Close a menu or panel, or leave the mode"],
  ]
}
