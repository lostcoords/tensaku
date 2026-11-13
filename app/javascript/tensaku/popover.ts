// Popovers above the toolbar: one at a time, closed by a second click on its button, Escape or a
// click elsewhere (closeOutside, which index.ts adds once the overlay boots).

import { div, fixed } from "./ui"

let popover: HTMLElement | null = null
let popoverTool: HTMLElement | null = null
let rendered: () => Node[] = () => []

export const popoverOpen = (tool?: HTMLElement) => tool ? popoverTool === tool : Boolean(popover)

export function closePopover() {
  popover?.remove()
  popover = null
  popoverTool?.setAttribute("aria-pressed", "false")
  popoverTool = null
}

// Opens render's content above dock for tool, or closes it when it is already open for tool.
export function togglePopover(tool: HTMLElement, dock: HTMLElement, render: () => Node[]) {
  const same = popoverTool === tool
  closePopover()
  if (same) return
  rendered = render
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

// Renders the open popover again, when it belongs to tool (or any tool).
export function redrawPopover(tool?: HTMLElement) {
  if (popover && (!tool || popoverTool === tool)) popover.replaceChildren(...rendered())
}

export function closeOutside(event: Event) {
  if (popover && !event.composedPath().some((node) => node === popover || node === popoverTool)) closePopover()
}

export const ago = (date: Date) => {
  const seconds = Math.round((Date.now() - date.getTime()) / 1000)
  return seconds < 60 ? "just now" : seconds < 3600 ? `${Math.round(seconds / 60)} min ago` : `${Math.round(seconds / 3600)} h ago`
}
