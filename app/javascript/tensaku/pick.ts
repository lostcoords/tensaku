// Picking a note's element again: after Pick again on its card, the next click on the page chooses
// the element, in any mode. index.ts routes that click and Escape here.

import { toast } from "./ui"

let picking: ((element: Element, at: DOMRect) => void) | null = null
let hint: HTMLElement | null = null
const listeners: (() => void)[] = []

export const isPicking = () => picking !== null
export const onPick = (listener: () => void) => { listeners.push(listener) }

export function startPick(done: (element: Element, at: DOMRect) => void) {
  stop()
  picking = done
  hint = toast("Click the element this note is about. Esc cancels.", { timeout: 0 })
  listeners.forEach((listener) => listener())
}

export function pick(element: Element, at: DOMRect) {
  const done = picking
  stop()
  done?.(element, at)
}

// Returns whether a pick was waiting.
export function cancelPick(): boolean {
  if (!picking) return false
  stop()
  return true
}

function stop() {
  picking = null
  hint?.remove()
  hint = null
  listeners.forEach((listener) => listener())
}
