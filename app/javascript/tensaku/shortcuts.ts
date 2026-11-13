// Keyboard shortcuts for the toolbar's tools. Each is modifier keys and a KeyboardEvent#code, such as
// "alt+shift+KeyT". The defaults can be changed or removed per browser, in the settings panel.

import { isApple } from "./api"
import { changeSettings, settings } from "./settings"

export const SHORTCUT_TOOLS = {
  select: "Select",
  edit: "Edit",
  notes: "Notes",
  agents: "Agents",
  pins: "Hide or show pins",
  clear: "Delete this page's notes",
  pause: "Pause animations",
  history: "Edit history",
  settings: "Settings",
} as const
export type ShortcutTool = keyof typeof SHORTCUT_TOOLS

const DEFAULTS: Partial<Record<ShortcutTool, string>> = { select: "alt+shift+KeyT", edit: "alt+shift+KeyE", notes: "alt+shift+KeyN" }

// The tool's shortcut in this browser. Null when it has none.
export function shortcutFor(tool: ShortcutTool): string | null {
  const own = settings().shortcuts
  return tool in own ? own[tool]! : DEFAULTS[tool] ?? null
}

export const isDefault = (tool: ShortcutTool) => !(tool in settings().shortcuts)

// Gives the tool these keys, or none with null. A tool that had the same keys loses them, and its
// name is returned.
export function setShortcut(tool: ShortcutTool, keys: string | null): ShortcutTool | null {
  const shortcuts = { ...settings().shortcuts }
  const taken = keys ? toolFor(keys) : null
  if (taken && taken !== tool) shortcuts[taken] = null
  if (keys === (DEFAULTS[tool] ?? null)) delete shortcuts[tool]
  else shortcuts[tool] = keys
  changeSettings({ shortcuts })
  return taken && taken !== tool ? taken : null
}

export const resetShortcuts = () => changeSettings({ shortcuts: {} })

function toolFor(keys: string): ShortcutTool | null {
  return (Object.keys(SHORTCUT_TOOLS) as ShortcutTool[]).find((tool) => shortcutFor(tool) === keys) ?? null
}

// The tool whose shortcut the key press is, if any.
export function toolForEvent(event: KeyboardEvent): ShortcutTool | null {
  return event.code ? toolFor(keysOf(event)) : null
}

export function keysOf(event: KeyboardEvent): string {
  const modifiers = [event.ctrlKey && "ctrl", event.altKey && "alt", event.shiftKey && "shift", event.metaKey && "meta"].filter(Boolean)
  return [...modifiers, event.code].join("+")
}

export const isModifierKey = (event: KeyboardEvent) => ["Alt", "Shift", "Control", "Meta"].includes(event.key)
// Alt, Ctrl or Cmd, so typing in the page never triggers a shortcut.
export const hasCommandModifier = (event: KeyboardEvent) => event.altKey || event.ctrlKey || event.metaKey

const APPLE_KEYS: Record<string, string> = { alt: "⌥", shift: "⇧", ctrl: "⌃", meta: "⌘" }
const OTHER_KEYS: Record<string, string> = { alt: "Alt", shift: "Shift", ctrl: "Ctrl", meta: "Meta" }

// Keys in the platform's own notation: ⌥⇧T on Apple platforms, Alt+Shift+T elsewhere.
export function keysLabel(keys: string): string {
  const parts = keys.split("+")
  const key = parts.pop()!.replace(/^(Key|Digit)/, "")
  const names = isApple ? APPLE_KEYS : OTHER_KEYS
  return [...parts.map((part) => names[part] ?? part), key].join(isApple ? "" : "+")
}
