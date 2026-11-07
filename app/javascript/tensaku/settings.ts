// The overlay's settings, kept per browser in localStorage.

import { storage, store } from "./ui"

export interface Settings {
  // Copied Markdown: every target and the thread, or one line per note.
  copyFormat: "detailed" | "short"
  // A browser notification when an agent answers while the tab is in the background.
  notify: boolean
  // The corner button shrinks to a small tab until the pointer comes near.
  compact: boolean
}

const DEFAULTS: Settings = { copyFormat: "detailed", notify: false, compact: false }
let current: Settings = { ...DEFAULTS, ...storage<Partial<Settings>>("settings", {}) }
const listeners: ((settings: Settings) => void)[] = []

export const settings = () => current
export const onSettings = (listener: (settings: Settings) => void) => { listeners.push(listener); listener(current) }

export function changeSettings(change: Partial<Settings>) {
  current = { ...current, ...change }
  store("settings", current)
  listeners.forEach((listener) => listener(current))
}
