// The overlay's own UI lives in a shadow root on an element attached to <html>, outside <body>, so
// Turbo body swaps and morphs never touch it and the app's CSS can't reach it.

const CSS = `
:host { all: initial; }
* { box-sizing: border-box; }
[hidden] { display: none !important; }

/* The pencil case (ART_STYLE.md). Tensaku keeps one look on every host page: a dark tray for the
   tools, Post-it paper for notes, and a few inks. */
:host {
  --tray: #1d1b19; --tray-raised: #2b2825; --tray-line: #3b3732; --tray-ink: #efe9dd; --tray-muted: #a69e90;
  --paper: #fffdf6; --ink: #24201b; --muted: #6f675a; --line: #e4ddcd;
  --akaji: #e0344f; --akaji-soft: rgba(224, 52, 79, .12);
  --marker: #ffe14d; --marker-edge: #d9a900; --marker-soft: rgba(255, 225, 77, .26);
  --question: #4c7df0; --resolved: #2fa872;
  --postit: #fff1a1; --postit-edge: #ecd66a; --postit-question: #ffdbe3; --postit-question-edge: #f1b3c2; --postit-resolved: #d3f1df; --postit-resolved-edge: #9fd8b8;
  --sans: ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
  --mono: ui-monospace, SFMono-Regular, Menlo, monospace;
  --spring: cubic-bezier(.34, 1.56, .64, 1);
}
.layer { position: absolute; left: 0; top: 0; width: 0; height: 0; z-index: 2147483000; font: 13px/1.45 var(--sans); color: var(--ink); }
.fixed { position: fixed; inset: 0; pointer-events: none; z-index: 2147483001; font: 13px/1.45 var(--sans); color: var(--ink); }
.fixed > * { pointer-events: auto; }

.icon { width: 20px; height: 20px; flex: none; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }
.icon .ink { fill: var(--ink-color, currentColor); stroke: currentColor; }
.icon .ink[stroke-width] { fill: none; stroke: var(--ink-color, currentColor); }

button { font: inherit; color: inherit; background: none; border: 1px solid var(--line); border-radius: 8px; padding: 4px 10px; cursor: pointer; transition: background-color .12s, border-color .12s, transform .16s var(--spring); }
button:hover { border-color: var(--ink); }
button:focus-visible { outline: 2px solid var(--question); outline-offset: 2px; }
button.primary { background: var(--tray); color: var(--tray-ink); border-color: var(--tray); font-weight: 600; }
button.primary:hover { background: #000; }
button.primary:disabled { opacity: .4; cursor: default; }
button.link { border: none; padding: 0; text-decoration: underline; color: var(--muted); }
button.quiet { border-color: transparent; color: var(--muted); }
button.quiet:hover { color: var(--ink); border-color: transparent; background: rgba(0, 0, 0, .06); }
button.icon-button { display: inline-grid; place-items: center; width: 28px; height: 28px; padding: 0; border: none; border-radius: 7px; color: var(--muted); }
button.icon-button:hover { background: rgba(0, 0, 0, .08); color: var(--ink); }
button.icon-button .icon { width: 17px; height: 17px; }
textarea, input { font: inherit; color: var(--ink); background: var(--paper); border: 1px solid var(--line); border-radius: 8px; padding: 7px 9px; width: 100%; resize: vertical; }
textarea:focus, input:focus { outline: 2px solid var(--question); outline-offset: -1px; }
kbd { font: 10.5px/1 var(--mono); padding: 2px 4px; border-radius: 4px; background: rgba(255, 255, 255, .12); color: inherit; opacity: .8; }

/* Marks on the page: highlighter for annotating, red pen for editing. */
.box { position: absolute; pointer-events: none; border: 1.5px solid var(--marker-edge); background: var(--marker-soft); border-radius: 4px; }
.box.edit { border: 1.5px dashed var(--akaji); background: transparent; }
.box.hover-edit { border: 1.5px solid var(--akaji); background: var(--akaji-soft); }
.box.selected { border-width: 2px; }
.label { position: absolute; transform: translateY(calc(-100% - 4px)); display: flex; gap: 6px; align-items: baseline; background: var(--tray); color: var(--tray-ink); font: 600 11px/1.3 var(--sans); padding: 3px 8px; border-radius: 6px; white-space: nowrap; pointer-events: none; max-width: 560px; overflow: hidden; text-overflow: ellipsis; box-shadow: 0 4px 12px rgba(0, 0, 0, .25); }
.label .where { font: 400 11px/1.3 var(--mono); color: var(--tray-muted); }
.area { position: absolute; border: 2px dashed var(--marker-edge); background: var(--marker-soft); border-radius: 4px; pointer-events: none; }

.panel { position: absolute; background: var(--paper); border: 1px solid var(--line); border-radius: 12px; box-shadow: 0 18px 40px -12px rgba(0, 0, 0, .35), 0 2px 6px rgba(0, 0, 0, .1); padding: 10px; min-width: 260px; max-width: 460px; }
.panel h3 { margin: 0 0 6px; font-size: 12px; font-weight: 600; color: var(--muted); }
.panel .row { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin-top: 8px; }
.panel .row.end { justify-content: flex-end; }
.panel .meta { font: 11px/1.4 var(--mono); color: var(--muted); word-break: break-all; }
.panel .warn { font-size: 12px; color: var(--akaji); margin-top: 6px; }

/* Post-it paper: the note form, note cards and the notes panel's cards. The folded corner sits at the
   bottom right; text and fields stay aligned to the square edges. */
.postit { position: relative; background: var(--postit); border: 1px solid var(--postit-edge); border-radius: 3px 3px 16px 3px; color: var(--ink); }
.postit::after { content: ""; position: absolute; right: -1px; bottom: -1px; width: 18px; height: 18px; border-radius: 0 0 16px 0; background: linear-gradient(135deg, rgba(0, 0, 0, .12) 0 50%, transparent 50%); pointer-events: none; }
.postit.question { background: var(--postit-question); border-color: var(--postit-question-edge); }
.postit.resolved { background: var(--postit-resolved); border-color: var(--postit-resolved-edge); }
.postit textarea { background: rgba(255, 255, 255, .6); border-color: var(--postit-edge); }
.postit button:not(.primary):not(.icon-button) { border-color: rgba(0, 0, 0, .16); background: rgba(255, 255, 255, .45); }
.postit button:not(.primary):not(.icon-button):hover { background: rgba(255, 255, 255, .8); border-color: rgba(0, 0, 0, .35); }

.note-form { width: 320px; max-width: calc(100vw - 16px); padding: 10px 12px 12px; box-shadow: 0 18px 40px -14px rgba(0, 0, 0, .45), 0 2px 6px rgba(0, 0, 0, .12); animation: settle .22s var(--spring); }
.note-form .head { display: flex; gap: 6px; align-items: center; margin-bottom: 8px; }
.note-form .head .what { flex: 1; min-width: 0; }
.note-form .head .title { font-weight: 600; font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.note-form .head .where { font: 11px/1.3 var(--mono); color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.note-form .head .tools { display: flex; gap: 1px; }
.note-form .foot { display: flex; gap: 6px; align-items: center; margin-top: 8px; }
.note-form .foot .hint { flex: 1; font-size: 11px; color: var(--muted); }

.note-pop { padding: 0; background: none; border: none; box-shadow: none; min-width: 280px; }
.note-pop .note-card { box-shadow: 0 18px 40px -14px rgba(0, 0, 0, .45); animation: settle .2s var(--spring); }
.note-card { padding: 12px 14px 14px; }
.note-card .comment { white-space: pre-wrap; margin-top: 6px; }
.note-card .reply { margin-top: 8px; padding: 6px 9px; border-left: 3px solid var(--resolved); background: rgba(255, 255, 255, .55); border-radius: 0 6px 6px 0; white-space: pre-wrap; }
.note-card .reply.question { border-color: var(--question); }
.note-card .row { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin-top: 10px; }
.note-card .row:first-child { margin-top: 0; }
.note-card .meta { font: 11px/1.4 var(--mono); color: var(--muted); word-break: break-all; }
.note-card textarea { margin-top: 8px; }
.status { display: inline-flex; align-items: center; gap: 4px; font: 700 10px/1 var(--sans); text-transform: uppercase; letter-spacing: .05em; padding: 3px 6px; border-radius: 999px; background: rgba(0, 0, 0, .08); color: var(--ink); }
.status.question { color: var(--question); }
.status.resolved { color: var(--resolved); }
.status .icon { width: 13px; height: 13px; stroke-width: 2.4; }

.panel.menu { background: var(--tray); color: var(--tray-ink); border-color: var(--tray-line); padding: 6px; min-width: 240px; animation: settle .16s var(--spring); }
.menu { display: flex; flex-direction: column; gap: 1px; }
.menu h3 { display: flex; flex-direction: column; gap: 2px; margin: 2px 6px 6px; color: var(--tray-ink); font-size: 12px; }
.menu h3 .where { font: 400 11px/1.3 var(--mono); color: var(--tray-muted); word-break: break-all; }
.menu button { display: flex; gap: 10px; align-items: center; width: 100%; text-align: left; border: none; border-radius: 7px; padding: 7px 8px; color: var(--tray-ink); }
.menu button span { flex: 1; }
.menu button .icon { width: 17px; height: 17px; color: var(--tray-muted); }
.menu button:hover, .menu button:focus-visible { background: var(--tray-raised); outline: none; }
.menu button:hover .icon, .menu button:focus-visible .icon { color: var(--tray-ink); }

/* The inline editor: paper with the red pen's edge. */
.editor { padding: 0; min-width: 0; max-width: none; border: 1.5px solid var(--akaji); border-radius: 10px; overflow: hidden; animation: settle .18s var(--spring); }
.editor .surface { padding: 8px 10px; white-space: pre-wrap; outline: none; min-height: 1.4em; }
.editor .bar { display: flex; gap: 8px; align-items: center; justify-content: space-between; border-top: 1px solid var(--line); background: #f8f4ea; padding: 6px 8px 6px 10px; font: 11px/1.3 var(--sans); color: var(--muted); }
.editor .bar .actions { display: flex; gap: 6px; }
.editor .bar button { font-size: 12px; padding: 3px 10px; border-radius: 999px; }
.editor .bar button.primary { background: var(--akaji); border-color: var(--akaji); color: #fff; }
.editor .bar button.primary:hover { background: #c41e3a; }
.editable { outline: none; border-bottom: 1.5px dotted var(--akaji); min-width: .5em; display: inline; }
.editable:focus { background: var(--akaji-soft); border-bottom-style: solid; }
.chip { display: inline-block; font: 11px/1.6 var(--mono); color: var(--muted); background: #f1ece0; border: 1px solid var(--line); border-radius: 5px; padding: 0 5px; margin: 0 1px; vertical-align: baseline; user-select: none; cursor: default; white-space: nowrap; }
.locale { display: grid; grid-template-columns: 32px 1fr; gap: 4px 6px; align-items: start; padding: 6px 10px; border-top: 1px solid var(--line); font: 13px/1.4 var(--sans); }
.locale .code { font: 11px var(--mono); color: var(--muted); padding-top: 2px; }
.attr { display: grid; grid-template-columns: 90px 1fr; gap: 6px; align-items: baseline; margin-top: 6px; }
.attr .name { font: 11px var(--mono); color: var(--muted); }
.attr .value { border: 1px solid var(--line); border-radius: 6px; padding: 4px 6px; white-space: pre-wrap; }

/* Pins: dropped where a note points, red while open, green with a drawn check once resolved. */
.pin { position: absolute; display: grid; place-items: center; width: 24px; height: 24px; padding: 0; border-radius: 50%; border: 2px solid #fff; background: var(--akaji); color: #fff; font: 700 11px/1 var(--sans); cursor: pointer; box-shadow: 0 3px 8px rgba(0, 0, 0, .3); transform: translate(-50%, -50%); }
.pin:hover { transform: translate(-50%, -50%) scale(1.12); border-color: #fff; }
.pin.fresh { animation: pin-drop .32s var(--spring); }
.pin.question { background: var(--question); }
.pin.resolved { background: var(--resolved); }
.pin .icon { width: 16px; height: 16px; stroke-width: 2.6; }
.pin.fresh .stroke { stroke-dasharray: 24; stroke-dashoffset: 24; animation: draw .42s .12s ease-out forwards; }

/* The tray. The corner button opens it; the selected tool rises and shows its ink. */
.dock { position: fixed; display: flex; align-items: center; gap: 8px; user-select: none; }
.corner { width: 40px; height: 40px; border-radius: 50%; border: 1px solid var(--tray-line); background: var(--tray); color: var(--akaji); font: 600 19px/38px "Hiragino Mincho ProN", "Yu Mincho", serif; text-align: center; cursor: grab; box-shadow: 0 8px 22px rgba(0, 0, 0, .3); position: relative; padding: 0; }
.corner:hover { border-color: var(--tray-muted); transform: rotate(-8deg); }
.corner.active { background: var(--akaji); color: #fff; border-color: var(--akaji); }
.corner .count { position: absolute; top: -5px; right: -5px; min-width: 18px; height: 18px; border-radius: 9px; background: var(--marker); color: var(--ink); font: 700 10px/18px var(--sans); padding: 0 5px; box-shadow: 0 1px 3px rgba(0, 0, 0, .3); }
.toolbar { display: flex; align-items: center; gap: 2px; background: var(--tray); border: 1px solid var(--tray-line); border-radius: 999px; padding: 5px; box-shadow: 0 12px 30px -8px rgba(0, 0, 0, .45); animation: settle .2s var(--spring); }
.toolbar .sep { width: 1px; height: 20px; background: var(--tray-line); margin: 0 4px; }
.tool { position: relative; display: grid; place-items: center; width: 38px; height: 38px; padding: 0; border: none; border-radius: 50%; color: var(--tray-ink); }
.tool:hover { background: var(--tray-raised); transform: translateY(-2px) rotate(-6deg); }
.tool[aria-pressed="true"] { background: var(--tray-raised); transform: translateY(-4px); }
.tool[aria-pressed="true"]::after { content: ""; position: absolute; bottom: 3px; left: 50%; width: 14px; height: 3px; margin-left: -7px; border-radius: 2px; background: var(--ink-color, var(--tray-ink)); }
.tool .icon { width: 22px; height: 22px; }
.tool .badge { position: absolute; top: 2px; right: 1px; min-width: 16px; height: 16px; border-radius: 8px; background: var(--akaji); color: #fff; font: 700 9.5px/16px var(--sans); padding: 0 4px; }
.tool .tip { position: absolute; bottom: calc(100% + 10px); left: 50%; transform: translateX(-50%) translateY(4px); display: flex; gap: 6px; align-items: center; background: var(--tray); color: var(--tray-ink); border: 1px solid var(--tray-line); font: 600 12px/1 var(--sans); padding: 6px 8px; border-radius: 7px; white-space: nowrap; pointer-events: none; opacity: 0; transition: opacity .12s, transform .12s; }
.tool:hover .tip, .tool:focus-visible .tip { opacity: 1; transform: translateX(-50%); }
.tool:focus-visible { outline: 2px solid var(--marker); outline-offset: 1px; }

/* The notes panel: the tray's material, holding the page's Post-its. */
.sidebar { position: fixed; top: 12px; right: 12px; bottom: 70px; width: 360px; max-width: calc(100vw - 24px); overflow: auto; background: var(--tray); color: var(--tray-ink); border: 1px solid var(--tray-line); border-radius: 16px; box-shadow: 0 24px 50px -16px rgba(0, 0, 0, .55); padding: 14px; animation: slide-in .22s var(--spring); }
.sidebar header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
.sidebar header strong { font-size: 14px; }
.sidebar header .icon-button { color: var(--tray-muted); }
.sidebar header .icon-button:hover { background: var(--tray-raised); color: var(--tray-ink); }
.sidebar > .row { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 12px; }
.sidebar > .row button { border-color: var(--tray-line); color: var(--tray-ink); font-size: 12px; }
.sidebar > .row button:hover { border-color: var(--tray-muted); background: var(--tray-raised); }
.sidebar .note-card { margin-bottom: 10px; }
.sidebar .empty { color: var(--tray-muted); padding: 12px 2px; line-height: 1.5; }

.toasts { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%); display: flex; flex-direction: column; gap: 6px; align-items: center; }
.toast { background: var(--tray); color: var(--tray-ink); border: 1px solid var(--tray-line); border-radius: 999px; padding: 8px 14px; box-shadow: 0 10px 26px -8px rgba(0, 0, 0, .45); display: flex; gap: 10px; align-items: center; max-width: 560px; animation: settle .2s var(--spring); }
.toast.error { background: var(--akaji); border-color: var(--akaji); color: #fff; border-radius: 12px; }
.toast button { color: inherit; border-color: currentColor; padding: 1px 9px; font-size: 12px; border-radius: 999px; }

@keyframes settle { from { opacity: 0; transform: translateY(6px) rotate(-1.2deg); } to { opacity: 1; transform: none; } }
@keyframes slide-in { from { opacity: 0; transform: translateX(16px); } to { opacity: 1; transform: none; } }
@keyframes pin-drop { from { opacity: 0; transform: translate(-50%, -140%) scale(.6); } to { opacity: 1; transform: translate(-50%, -50%); } }
@keyframes draw { to { stroke-dashoffset: 0; } }

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation: none !important; transition: none !important; }
  .pin.fresh .stroke { stroke-dashoffset: 0; }
  .tool:hover, .tool[aria-pressed="true"], .corner:hover { transform: none; }
}
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
