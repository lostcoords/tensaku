// The overlay's own UI lives in a shadow root on an element attached to <html>, outside <body>, so
// Turbo body swaps and morphs never touch it and the app's CSS can't reach it.

const CSS = `
:host { all: initial; }
* { box-sizing: border-box; }
[hidden] { display: none !important; }
.layer { position: absolute; left: 0; top: 0; width: 0; height: 0; z-index: 2147483000; font: 13px/1.4 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; color: var(--ink); }
.fixed { position: fixed; inset: 0; pointer-events: none; z-index: 2147483001; font: 13px/1.4 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; color: var(--ink); }
.fixed > * { pointer-events: auto; }
:host {
  --paper: #fffdf8; --ink: #22201c; --muted: #6f6a60; --line: #ddd6c8;
  --akaji: #c41e3a; --akaji-soft: rgba(196, 30, 58, .10); --pencil: #4b5563; --pencil-soft: rgba(75, 85, 99, .10);
  --question: #1d4ed8; --resolved: #15803d;
}
@media (prefers-color-scheme: dark) {
  :host { --paper: #1f1d1a; --ink: #f3efe6; --muted: #aaa294; --line: #3b3731; --akaji: #ff5d73; --akaji-soft: rgba(255, 93, 115, .14); --pencil: #c4c9d1; --pencil-soft: rgba(196, 201, 209, .14); --question: #7aa2ff; --resolved: #4ade80; }
}
button { font: inherit; color: inherit; background: none; border: 1px solid var(--line); border-radius: 6px; padding: 3px 8px; cursor: pointer; }
button:hover { border-color: var(--ink); }
button.primary { background: var(--ink); color: var(--paper); border-color: var(--ink); }
button.link { border: none; padding: 0; text-decoration: underline; color: var(--muted); }
textarea, input { font: inherit; color: var(--ink); background: var(--paper); border: 1px solid var(--line); border-radius: 6px; padding: 6px 8px; width: 100%; }
textarea:focus, input:focus { outline: 2px solid var(--pencil); outline-offset: -1px; }

.box { position: absolute; pointer-events: none; border: 1.5px solid var(--pencil); background: var(--pencil-soft); border-radius: 3px; }
.box.edit { border: 1.5px dashed var(--akaji); background: transparent; }
.box.hover-edit { border-color: var(--akaji); background: var(--akaji-soft); }
.box.selected { border-width: 2px; }
.label { position: absolute; transform: translateY(-100%); background: var(--ink); color: var(--paper); font-size: 11px; padding: 1px 6px; border-radius: 4px 4px 4px 0; white-space: nowrap; pointer-events: none; max-width: 520px; overflow: hidden; text-overflow: ellipsis; }
.area { position: absolute; border: 1.5px dashed var(--pencil); background: var(--pencil-soft); pointer-events: none; }

.panel { position: absolute; background: var(--paper); border: 1px solid var(--line); border-radius: 10px; box-shadow: 0 12px 32px rgba(0,0,0,.18); padding: 10px; min-width: 260px; max-width: 460px; }
.panel h3 { margin: 0 0 6px; font-size: 12px; font-weight: 600; color: var(--muted); }
.panel .row { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin-top: 8px; }
.panel .row.end { justify-content: flex-end; }
.panel .meta { font-size: 11px; color: var(--muted); word-break: break-all; }
.panel .warn { font-size: 12px; color: var(--akaji); margin-top: 6px; }
.menu { display: flex; flex-direction: column; gap: 4px; min-width: 200px; }
.menu button { text-align: left; border: none; padding: 5px 8px; }
.menu button:hover { background: var(--pencil-soft); }
.menu kbd { float: right; color: var(--muted); font: 11px ui-monospace, monospace; }

.editor { padding: 0; min-width: 0; max-width: none; border-color: var(--akaji); }
.editor .surface { padding: 6px 8px; white-space: pre-wrap; outline: none; min-height: 1.4em; }
.editor .bar { display: flex; gap: 6px; align-items: center; justify-content: space-between; border-top: 1px solid var(--line); padding: 5px 8px; font: 11px/1.3 ui-sans-serif, system-ui, sans-serif; color: var(--muted); }
.editor .bar .actions { display: flex; gap: 6px; }
.editor .bar button { font-size: 11px; padding: 2px 7px; }
.editable { outline: none; border-bottom: 1px dotted var(--akaji); min-width: .5em; display: inline; }
.editable:focus { background: var(--akaji-soft); }
.chip { display: inline-block; font: 11px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--muted); background: var(--pencil-soft); border: 1px solid var(--line); border-radius: 4px; padding: 0 4px; margin: 0 1px; vertical-align: baseline; user-select: none; cursor: default; white-space: nowrap; }
.locale { display: grid; grid-template-columns: 32px 1fr; gap: 4px 6px; align-items: start; padding: 6px 8px; border-top: 1px solid var(--line); font: 13px/1.4 ui-sans-serif, system-ui, sans-serif; }
.locale .code { font: 11px ui-monospace, monospace; color: var(--muted); padding-top: 2px; }
.attr { display: grid; grid-template-columns: 90px 1fr; gap: 6px; align-items: baseline; margin-top: 6px; }
.attr .name { font: 11px ui-monospace, monospace; color: var(--muted); }
.attr .value { border: 1px solid var(--line); border-radius: 6px; padding: 4px 6px; white-space: pre-wrap; }

.pin { position: absolute; width: 22px; height: 22px; border-radius: 11px 11px 11px 2px; background: var(--pencil); color: var(--paper); font: 600 11px/22px ui-sans-serif, system-ui, sans-serif; text-align: center; cursor: pointer; box-shadow: 0 2px 6px rgba(0,0,0,.25); transform: translate(-4px, -100%); }
.pin.question { background: var(--question); }
.pin.resolved { background: var(--resolved); }
.note-card .comment { white-space: pre-wrap; }
.note-card .reply { margin-top: 6px; padding: 6px 8px; border-left: 3px solid var(--resolved); background: var(--pencil-soft); white-space: pre-wrap; }
.note-card .reply.question { border-color: var(--question); }
.status { font: 600 10px/1 ui-sans-serif, system-ui, sans-serif; text-transform: uppercase; letter-spacing: .04em; padding: 2px 5px; border-radius: 4px; background: var(--pencil-soft); color: var(--pencil); }
.status.question { color: var(--question); }
.status.resolved { color: var(--resolved); }

.dock { position: fixed; display: flex; align-items: center; gap: 6px; user-select: none; }
.corner { width: 36px; height: 36px; border-radius: 18px; border: 1px solid var(--line); background: var(--paper); color: var(--akaji); font: 600 17px/34px "Hiragino Mincho ProN", "Yu Mincho", serif; text-align: center; cursor: grab; box-shadow: 0 4px 14px rgba(0,0,0,.18); position: relative; padding: 0; }
.corner.active { background: var(--akaji); color: var(--paper); border-color: var(--akaji); }
.corner .count { position: absolute; top: -4px; right: -4px; min-width: 16px; height: 16px; border-radius: 8px; background: var(--pencil); color: var(--paper); font: 600 10px/16px ui-sans-serif, system-ui, sans-serif; padding: 0 4px; }
.toolbar { display: flex; gap: 4px; background: var(--paper); border: 1px solid var(--line); border-radius: 18px; padding: 4px; box-shadow: 0 4px 14px rgba(0,0,0,.14); }
.toolbar button { border: none; border-radius: 14px; padding: 4px 10px; }
.toolbar button[aria-pressed="true"] { background: var(--ink); color: var(--paper); }
.sidebar { position: fixed; top: 12px; right: 12px; bottom: 64px; width: 360px; overflow: auto; background: var(--paper); border: 1px solid var(--line); border-radius: 12px; box-shadow: 0 12px 32px rgba(0,0,0,.18); padding: 12px; }
.sidebar header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
.sidebar header strong { font-size: 14px; }
.sidebar .note-card { border-top: 1px solid var(--line); padding: 10px 0; }
.sidebar .empty { color: var(--muted); padding: 12px 0; }
.toasts { position: fixed; left: 50%; bottom: 16px; transform: translateX(-50%); display: flex; flex-direction: column; gap: 6px; align-items: center; }
.toast { background: var(--ink); color: var(--paper); border-radius: 8px; padding: 7px 12px; box-shadow: 0 6px 18px rgba(0,0,0,.2); display: flex; gap: 10px; align-items: center; max-width: 560px; }
.toast.error { background: var(--akaji); }
.toast button { color: inherit; border-color: currentColor; padding: 1px 7px; font-size: 12px; }
`

export const host = document.createElement("tensaku-overlay")
host.id = "tensaku-overlay"
host.setAttribute("data-tensaku-ui", "")
host.setAttribute("data-turbo-permanent", "")
export const shadow = host.attachShadow({ mode: "open" })

const style = document.createElement("style")
style.textContent = CSS
export const layer = div("layer")
export const fixed = div("fixed")
const toasts = div("toasts")
shadow.append(style, layer, fixed)
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

export function toast(message: string, options: { error?: boolean; actions?: Record<string, () => void>; timeout?: number } = {}) {
  const element = div("toast" + (options.error ? " error" : ""), h("span", {}, message))
  element.setAttribute("role", options.error ? "alert" : "status")
  for (const [label, action] of Object.entries(options.actions ?? {})) {
    element.append(h("button", { onclick: () => { element.remove(); action() } }, label))
  }
  toasts.append(element)
  setTimeout(() => element.remove(), options.timeout ?? (options.error ? 8000 : 5000))
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

export function box(rect: DOMRect, className: string, label?: string) {
  const element = div("box " + className)
  Object.assign(element.style, { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px`, height: `${rect.height}px` })
  layer.append(element)
  if (!label) return [element]
  const tag = div("label")
  tag.textContent = label
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
