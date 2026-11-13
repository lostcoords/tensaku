// The overlay's own UI lives in a shadow root on an element attached to <html>, outside <body>, so
// Turbo body swaps and morphs never touch it and the app's CSS can't reach it.

import CSS from "./overlay.css" with { type: "text" }

const host = document.createElement("tensaku-overlay")
host.id = "tensaku-overlay"
host.setAttribute("data-tensaku-ui", "")
host.setAttribute("data-turbo-permanent", "")
const shadow = host.attachShadow({ mode: "open" })

// A constructed stylesheet, so a page with a strict Content-Security-Policy (no 'unsafe-inline' for
// styles) still styles the overlay. Browsers without constructable stylesheets get a <style> element.
if ("adoptedStyleSheets" in shadow && typeof CSSStyleSheet !== "undefined" && "replaceSync" in CSSStyleSheet.prototype) {
  const sheet = new CSSStyleSheet()
  sheet.replaceSync(CSS)
  shadow.adoptedStyleSheets = [sheet]
} else {
  const style = document.createElement("style")
  style.textContent = CSS
  shadow.append(style)
}
export const layer = div("layer")
export const fixed = div("fixed")
const toasts = div("toasts")
shadow.append(layer, fixed)
fixed.append(toasts)

export function mount() {
  if (!host.isConnected) document.documentElement.append(host)
}

type Child = Node | string | null | undefined | false
export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attributes: Record<string, any> = {},
  ...children: Child[]
): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag)
  for (const [name, value] of Object.entries(attributes)) {
    if (value === undefined || value === null || value === false) continue
    if (name.startsWith("on") && typeof value === "function") element.addEventListener(name.slice(2), value)
    else if (name === "className") element.className = value
    else element.setAttribute(name, value === true ? "" : String(value))
  }
  for (const child of children) if (child) element.append(child)
  return element
}

export function div(className: string, ...children: Child[]) {
  return h("div", { className }, ...children)
}

export function toast(message: string, options: { error?: boolean; actions?: Record<string, () => void>; timeout?: number; detail?: HTMLElement } = {}) {
  const element = div("toast" + (options.error ? " error" : "") + (options.detail ? " detailed" : ""), h("span", {}, message))
  element.setAttribute("role", options.error ? "alert" : "status")
  for (const [label, action] of Object.entries(options.actions ?? {})) {
    element.append(h("button", { onclick: () => { element.remove(); action() } }, label))
  }
  if (options.detail) element.append(options.detail)
  toasts.append(element)
  // A timeout of 0 keeps the toast until the caller removes it.
  if (options.timeout !== 0) setTimeout(() => element.remove(), options.timeout ?? (options.error ? 8000 : 5000))
  return element
}

// A panel in document coordinates, placed under (or over) a rectangle and kept on screen.
export function panel(anchor: DOMRect, className: string, ...children: Child[]) {
  const element = div("panel " + className, ...children)
  layer.append(element)
  place(element, anchor)
  return element
}

export function place(element: HTMLElement, anchor: DOMRect, over = false) {
  const width = element.offsetWidth
  const left = Math.max(scrollX + 8, Math.min(anchor.left, scrollX + innerWidth - width - 8))
  let top = over ? anchor.top : anchor.bottom + 6
  if (!over && top + element.offsetHeight > scrollY + innerHeight - 8 && anchor.top - element.offsetHeight - 6 > scrollY) {
    top = anchor.top - element.offsetHeight - 6
  }
  element.style.left = `${left}px`
  element.style.top = `${top}px`
}

export function box(rect: DOMRect, className: string, label?: readonly [string, string]) {
  const element = div("box " + className)
  Object.assign(element.style, { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px`, height: `${rect.height}px` })
  layer.append(element)
  if (!label) return [element]
  const tag = div("label")
  tag.append(label[0])
  if (label[1]) tag.append(h("span", { className: "where" }, label[1]))
  Object.assign(tag.style, { left: `${rect.left}px`, top: `${rect.top}px` })
  layer.append(tag)
  return [element, tag]
}

export async function copy(text: string) {
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    const area = h("textarea", {}, text)
    shadow.append(area)
    area.select()
    document.execCommand("copy")
    area.remove()
  }
}

export function storage<T>(key: string, fallback: T): T {
  try {
    const value = localStorage.getItem(`tensaku:${key}`)
    return value ? (JSON.parse(value) as T) : fallback
  } catch {
    return fallback
  }
}

export function store(key: string, value: unknown) {
  try {
    localStorage.setItem(`tensaku:${key}`, JSON.stringify(value))
  } catch {
    // Private windows and blocked storage: positions just aren't remembered.
  }
}

export function activeInShadow(): Element | null {
  return shadow.activeElement
}
