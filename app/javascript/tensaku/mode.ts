// The overlay's mode: off, select (inspect) or edit. The dock, the inspector and the edit outlines
// follow it through onMode.

export type Mode = "off" | "inspect" | "edit"

let current: Mode = "off"
const listeners: ((mode: Mode) => void)[] = []

export const mode = () => current
export const onMode = (listener: (mode: Mode) => void) => listeners.push(listener)

export function setMode(next: Mode) {
  current = next
  listeners.forEach((listener) => listener(next))
}
