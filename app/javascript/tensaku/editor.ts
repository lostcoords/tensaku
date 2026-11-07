// Editing text in place. The editor always shows the source, never the rendered text: static text is
// editable, Ruby output, translation interpolations and child elements are locked chips.

import { api, ApiError, query } from "./api"
import { attributeKey, nodesForKey, elementsWithAttributeKey, type TranslationKey } from "./markers"
import { contentRect, copiesOf, editableAttributes, MARKDOWN, stampOf, STAMP, translationOf, utf8Length, editKind } from "./dom"
import { refresh, replaceText, type SourceKind } from "./refresh"
import { activeInShadow, div, h, layer, place, toast } from "./ui"

interface TextPiece { kind: "text"; start: number; end: number; raw: string; text: string; index?: number }
type Piece = TextPiece | { kind: "ruby"; code: string } | { kind: "element"; tag: string; label: string } | { kind: "hidden" }
interface Attribute { name: string; quote: string | null; pieces: Piece[] }
interface Description { file: string; stamp: string; range: string; tag: string; helper: boolean; editable: boolean; pieces: Piece[]; attributes: Attribute[] }
interface LocaleEntry { file?: string; line?: number; value: string | null; editable: boolean }
interface MarkdownDescription { file: string; range: string; editable: boolean; prefix: string; text: string; original: string }

interface Undo { label: string; run: () => Promise<void> }
const undos = new Map<string, Undo>()

// The saves made from this page, newest last. Each element keeps one undo, its latest edit, so only
// that entry can be undone from the history.
interface HistoryEntry { key: string; label: string; at: Date; file?: string; undone: boolean; undo: Undo }
const history: HistoryEntry[] = []
const HISTORY_LIMIT = 20

export function editHistory() {
  return history.slice().reverse().map((entry) => ({
    label: entry.label,
    at: entry.at,
    file: entry.file,
    undone: entry.undone,
    canUndo: !entry.undone && undos.get(entry.key) === entry.undo,
    run: () => entry.undo.run().catch(report),
  }))
}
let open: { element: HTMLElement; save: () => Promise<void>; close: () => void } | null = null

export function undoFor(element: Element): Undo | undefined {
  return undos.get(undoKey(element))
}

function undoKey(element: Element) {
  return element.getAttribute(STAMP) ?? element.getAttribute(MARKDOWN) ?? translationOf(element)?.key ?? ""
}

export function isEditing() {
  return open !== null
}

export function closeEditor() {
  open?.close()
}

export async function edit(element: Element, kind = editKind(element)) {
  closeEditor()
  try {
    if (kind === "translation") await editTranslation(element, translationOf(element)!)
    else if (kind === "markdown") await editMarkdown(element)
    else if (kind === "template") await editTemplate(element)
    else if (kind === "attributes") await editAttributes(element)
    else toast("This text comes from Ruby, so it can't be edited here. Leave a note instead.")
  } catch (error) {
    report(error)
  }
}

function report(error: unknown) {
  const message = error instanceof Error ? error.message : String(error)
  toast(message, { error: true, actions: error instanceof ApiError && error.stale ? { Reload: () => location.reload() } : undefined })
}

const normal = (text: string) => text.replace(/\s+/g, " ").trim()

// The server reads the file as it is now; the page shows what it was when it rendered. If the static
// text in the file no longer appears, in order, in what the page shows, the file changed in between,
// and editing it would overwrite a change the person hasn't seen.
function assertRendered(element: Element, texts: string[]) {
  const rendered = normal(element.textContent ?? "")
  let from = 0
  for (const text of texts.map(normal).filter(Boolean)) {
    const at = rendered.indexOf(text, from)
    if (at < 0) throw new ApiError("The file changed since the page was rendered. Reload the page and try again.", 409, true)
    from = at + text.length
  }
}

// A text field inside the editor: plain text only, Enter saves, Shift+Enter is a new line.
function field(text: string, multiline = false) {
  const span = h("span", { className: "editable", spellcheck: "true" }, text)
  span.contentEditable = "plaintext-only"
  if (span.contentEditable !== "plaintext-only") span.contentEditable = "true"
  span.dataset.original = text
  span.addEventListener("paste", (event) => {
    event.preventDefault()
    document.execCommand("insertText", false, event.clipboardData?.getData("text/plain") ?? "")
  })
  if (!multiline) span.addEventListener("keydown", (event) => { if (event.key === "Enter" && event.shiftKey) event.preventDefault() })
  return span
}

const valueOf = (span: HTMLElement) => (span.innerText ?? span.textContent ?? "").replace(/ /g, " ").replace(/\n$/, "")

function chip(label: string, title?: string) {
  return h("span", { className: "chip", title, contenteditable: "false" }, label)
}

// The colour behind an element: the first ancestor with a background that is mostly opaque.
function backgroundOf(element: Element) {
  for (let node: Element | null = element; node; node = node.parentElement) {
    const color = getComputedStyle(node).backgroundColor
    const alpha = color.match(/rgba?\([^)]*,\s*([\d.]+)\)/)?.[1]
    if (color !== "transparent" && (alpha === undefined || Number(alpha) > 0.6)) return color
  }
  return "#fff"
}

// The editor sits over the element in the page's own colours and type, so the text looks edited in
// place. Its padding is pulled out of the way so the source lines up with the rendered text. The
// status bar floats below it, in the toolbar's material.
const INSET = { x: 11.5, y: 9.5 }
function frame(element: Element, surface: HTMLElement, info: string, save: () => Promise<void>, extra: Node[] = [], warning?: string) {
  const rect = contentRect(element)
  const computed = getComputedStyle(element)
  Object.assign(surface.style, {
    fontFamily: computed.fontFamily, fontSize: computed.fontSize, fontWeight: computed.fontWeight,
    lineHeight: computed.lineHeight, letterSpacing: computed.letterSpacing, textAlign: computed.textAlign, color: computed.color,
  })
  surface.classList.add("surface")

  const status = h("span", {}, info)
  const close = () => { container.remove(); open = null; document.removeEventListener("keydown", keys, true) }
  const saveAndClose = async () => {
    if (container.dataset.saving) return
    container.dataset.saving = "1"
    status.textContent = "Saving…"
    try {
      await save()
      close()
    } catch (error) {
      delete container.dataset.saving
      status.textContent = info
      report(error)
    }
  }
  const container = div("panel editor",
    surface,
    ...extra,
    div("bar", h("span", {}, status, warning ? h("strong", { style: "color: var(--akaji)" }, ` · ${warning}`) : null),
      div("actions", h("button", { onclick: close, type: "button" }, "Cancel"), h("button", { className: "primary", onclick: saveAndClose, type: "button" }, "Save"))))
  container.setAttribute("role", "dialog")
  container.setAttribute("aria-label", "Tensaku editor")
  container.style.background = backgroundOf(element)
  container.style.color = computed.color
  container.style.minWidth = `${Math.max(rect.width + INSET.x * 2, 240)}px`
  container.style.maxWidth = `${Math.max(rect.width + INSET.x * 2, 480)}px`
  layer.append(container)
  place(container, new DOMRect(rect.left - INSET.x, rect.top - INSET.y, rect.width + INSET.x * 2, rect.height), true)

  const keys = (event: KeyboardEvent) => {
    if (!container.isConnected) return
    if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); close() }
    if (event.key !== "Enter" || !activeInShadow()?.classList.contains("editable")) return
    const newlines = surface.dataset.newlines !== undefined
    if (newlines ? event.metaKey || event.ctrlKey : !event.shiftKey) { event.preventDefault(); saveAndClose() }
  }
  document.addEventListener("keydown", keys, true)
  // Blur saves, unless focus moved to another part of the editor.
  container.addEventListener("focusout", () => {
    setTimeout(() => {
      const active = activeInShadow()
      if (container.isConnected && !container.dataset.saving && !(active && container.contains(active))) saveAndClose()
    }, 150)
  })
  open = { element: container, save: saveAndClose, close }
  ;(container.querySelector(".editable") as HTMLElement | null)?.focus()
  return container
}

function pieceSurface(pieces: Piece[]) {
  const surface = div("")
  const fields: { span: HTMLElement; piece: TextPiece }[] = []
  for (const piece of pieces) {
    if (piece.kind === "text") {
      const span = field(piece.text)
      fields.push({ span, piece })
      surface.append(span)
    } else if (piece.kind === "ruby") surface.append(chip(piece.code.length > 30 ? piece.code.slice(0, 29) + "…" : piece.code, piece.code))
    else if (piece.kind === "element") surface.append(chip(`<${piece.tag}>${piece.label ? " " + piece.label : ""}`, "Edit this element on its own"))
  }
  return { surface, fields }
}

// Template text --------------------------------------------------------------------------------

async function editTemplate(element: Element) {
  const stamp = stampOf(element)!
  const info = await api<Description>("GET", "/source" + query({ stamp: stamp.value }))
  indexPieces(info.pieces)
  if (!info.editable) {
    if (editableAttributes(element).length) return editAttributes(element)
    throw new Error(info.helper ? "This element comes from a helper, so its text can't be edited here." : "This element has no static text to edit.")
  }
  assertRendered(element, info.pieces.filter((p): p is TextPiece => p.kind === "text").map((p) => p.text))
  const { surface, fields } = pieceSurface(info.pieces)
  const copies = copiesOf(element)
  frame(element, surface, `${info.file}:${stamp.line}`, async () => {
    const changed = fields.filter(({ span, piece }) => valueOf(span) !== piece.text)
    if (!changed.length) return
    await saveTemplate(element, stamp.value, changed.map(({ span, piece }) => ({ piece, text: valueOf(span) })))
  }, [], copies > 1 ? `this edits all ${copies} copies` : undefined)
}

async function saveTemplate(element: Element, stamp: string, changes: { piece: TextPiece; text: string }[], isUndo = false) {
  const result = await api("POST", "/text", {
    stamp,
    edits: changes.map(({ piece, text }) => ({ start: piece.start, end: piece.end, original: piece.raw, text })),
  })
  const nodes = Array.from(document.querySelectorAll(`[${STAMP}="${CSS.escape(stamp)}"]`)).flatMap((el) =>
    Array.from(el.childNodes).filter((node): node is Text => node.nodeType === Node.TEXT_NODE))
  changes.forEach(({ piece, text }) => replaceText(nodes, piece.text, text))
  if (!isUndo) {
    remember(element, `Undo edit in ${stamp}`, async () => {
      const fresh = await api<Description>("GET", "/source" + query({ stamp }))
      const texts = fresh.pieces.filter((p): p is TextPiece => p.kind === "text")
      const reverse = changes.map(({ piece, text }) => {
        const now = texts[piece.index ?? -1]
        if (!now || now.text !== text) throw new ApiError("The text changed since the edit, so it can't be undone here.", 409, true)
        return { piece: { ...now, index: piece.index }, text: piece.text }
      })
      await saveTemplate(element, stamp, reverse, true)
    })
  }
  done(result, "template")
}

// Attributes -----------------------------------------------------------------------------------

async function editAttributes(element: Element) {
  const stamp = stampOf(element)
  const description = stamp ? await api<Description>("GET", "/source" + query({ stamp: stamp.value })) : null
  const names = editableAttributes(element)
  const rows: Node[] = []
  const savers: (() => Promise<void>)[] = []

  for (const name of names) {
    const key = attributeKey(element, name)
    if (key) {
      const entry = (await api<{ locales: Record<string, LocaleEntry> }>("GET", "/translation" + query({ key: key.key }))).locales[key.locale]
      if (!entry?.editable || entry.value === null) continue
      assertRendered(attributeNode(element, name), staticParts(entry.value))
      const { surface, read } = interpolationSurface(entry.value)
      rows.push(div("attr", h("span", { className: "name", title: `${key.locale}.${key.key}` }, `${name} (t)`), div("value", surface)))
      savers.push(async () => {
        const text = read()
        if (text !== entry.value) await saveTranslation(element, key, entry.value!, text)
      })
      continue
    }
    const attribute = description?.attributes.find((a) => a.name === name)
    if (!attribute || !attribute.pieces.some((p) => p.kind === "text")) continue
    assertRendered(attributeNode(element, name), attribute.pieces.filter((p): p is TextPiece => p.kind === "text").map((p) => p.text))
    const { surface, fields } = pieceSurface(attribute.pieces)
    rows.push(div("attr", h("span", { className: "name" }, name), div("value", surface)))
    savers.push(async () => {
      for (const { span, piece } of fields) {
        const text = valueOf(span)
        if (text === piece.text) continue
        const result = await api("POST", "/attribute", { stamp: stamp!.value, name, start: piece.start, end: piece.end, original: piece.raw, text })
        document.querySelectorAll(`[${STAMP}="${CSS.escape(stamp!.value)}"]`).forEach((el) => {
          const current = el.getAttribute(name)
          if (current !== null) el.setAttribute(name, current.replace(piece.text, text))
        })
        remember(element, `Undo ${name}`, async () => {
          const fresh = await api<Description>("GET", "/source" + query({ stamp: stamp!.value }))
          const now = fresh.attributes.find((a) => a.name === name)?.pieces.find((p): p is TextPiece => p.kind === "text" && p.text === text)
          if (!now) throw new ApiError("The attribute changed since the edit, so it can't be undone here.", 409, true)
          await api("POST", "/attribute", { stamp: stamp!.value, name, start: now.start, end: now.end, original: now.raw, text: piece.text })
          done({ changed: true }, "template")
        })
        done(result, "template")
        return
      }
    })
  }
  if (!rows.length) throw new Error("Nothing here can be edited. Leave a note instead.")

  const surface = div("")
  surface.append(...rows)
  frame(element, surface, description ? `${description.file}:${stamp!.line} attributes` : "attributes", async () => {
    for (const save of savers) await save()
  })
}

// Translations ---------------------------------------------------------------------------------

const INTERPOLATION = /(%\{[^}]+\})/

function interpolationSurface(value: string) {
  const surface = div("")
  for (const part of value.split(INTERPOLATION)) {
    if (!part) continue
    surface.append(INTERPOLATION.test(part) ? chip(part) : field(part, true))
  }
  if (!surface.querySelector(".editable")) surface.prepend(field("", true))
  const read = () => Array.from(surface.childNodes).map((node) => (node as HTMLElement).classList?.contains("chip") ? node.textContent : valueOf(node as HTMLElement)).join("")
  return { surface, read }
}

async function editTranslation(element: Element, key: TranslationKey) {
  const { locales } = await api<{ locales: Record<string, LocaleEntry> }>("GET", "/translation" + query({ key: key.key }))
  const entry = locales[key.locale]
  if (!entry?.editable || entry.value === null) {
    throw new Error(`${key.locale}.${key.key} isn't in a writable locale file (it may come from a gem).`)
  }
  assertRendered(element, staticParts(entry.value))
  const main = interpolationSurface(entry.value)
  const others = Object.entries(locales).filter(([locale]) => locale !== key.locale)
  const otherRows = div("")
  otherRows.hidden = true
  const otherReaders: { locale: string; entry: LocaleEntry; read: () => string }[] = []
  for (const [locale, other] of others) {
    if (other.editable && other.value !== null) {
      const surface = interpolationSurface(other.value)
      otherReaders.push({ locale, entry: other, read: surface.read })
      otherRows.append(div("locale", h("span", { className: "code" }, locale), surface.surface))
    } else {
      otherRows.append(div("locale", h("span", { className: "code" }, locale), h("em", { style: "color: var(--muted)" }, other.value === null ? "missing" : `${other.value} (not writable)`)))
    }
  }
  const toggle = others.length
    ? h("button", { className: "link", type: "button", onclick: () => { otherRows.hidden = !otherRows.hidden; toggle!.textContent = otherRows.hidden ? `Other locales (${others.length})` : "Hide other locales" } }, `Other locales (${others.length})`)
    : null
  const extra = toggle ? [div("locale", h("span", { className: "code" }, ""), toggle), otherRows] : []

  frame(element, main.surface, `${key.locale}.${key.key} · ${entry.file}:${entry.line}`, async () => {
    const text = main.read()
    if (text !== entry.value) await saveTranslation(element, key, entry.value!, text)
    for (const other of otherReaders) {
      const value = other.read()
      if (value !== other.entry.value) await api("POST", "/translation", { locale: other.locale, key: key.key, original: other.entry.value, text: value })
    }
  }, extra)
}

async function saveTranslation(element: Element, key: TranslationKey, original: string, text: string, isUndo = false) {
  const result = await api("POST", "/translation", { locale: key.locale, key: key.key, original, text })
  if (!INTERPOLATION.test(original)) {
    replaceText(nodesForKey(key), original, text)
    elementsWithAttributeKey(key).forEach(({ element: el, name }) => { if (el.getAttribute(name) === original) el.setAttribute(name, text) })
  }
  if (!isUndo) remember(element, `Undo ${key.key}`, () => saveTranslation(element, key, text, original, true))
  done(result, "translation")
}

// Markdown -------------------------------------------------------------------------------------

async function editMarkdown(element: Element) {
  const range = element.getAttribute(MARKDOWN)!
  const tag = element.tagName.toLowerCase()
  const info = await api<MarkdownDescription>("GET", "/markdown" + query({ range, tag }))
  if (!info.editable) throw new Error("This Markdown block can only get notes.")
  const words = info.text.replace(/^\s*(?:[-*+]|\d{1,9}[.)])\s+(?:\[[ xX]\]\s+)?/gm, "").replace(/\]\([^)]*\)/g, "").replace(/[*_`#>\[\]]/g, "")
  // Each line on its own: list items render without the line breaks between them.
  assertRendered(element, words.split("\n").map((line) => line.trim().split(/\s+/).slice(0, 6).join(" ")).slice(0, 8))
  const surface = div("")
  // A whole list is several lines of source: Enter starts a new item, Cmd/Ctrl+Enter saves.
  if (tag === "ul" || tag === "ol") surface.dataset.newlines = ""
  if (info.prefix.trim()) surface.append(chip(info.prefix.trim()), " ")
  const text = field(info.text, true)
  surface.append(text)
  frame(element, surface, `${info.file}:${info.range.split(":")[0]} (Markdown)`, async () => {
    const value = valueOf(text)
    if (value === info.text) return
    await saveMarkdown(element, range, info.original, info.prefix, value, info.text, false, tag)
  })
}

async function saveMarkdown(element: Element, range: string, original: string, prefix: string, text: string, previous: string, isUndo = false, tag?: string) {
  const result = await api("POST", "/markdown", { range, original, text, tag })
  if (!tag?.match(/^[uo]l$/) && !/[*_`\[\]<>#]/.test(previous + text)) replaceText(Array.from(element.childNodes).filter((n): n is Text => n.nodeType === Node.TEXT_NODE), previous, text)
  if (!isUndo) {
    remember(element, "Undo Markdown edit", async () => {
      const [, path, startLine, startColumn] = range.match(/^(.+):(\d+):(\d+)-/)!
      const source = prefix + text
      const lines = source.split("\n")
      const endLine = Number(startLine) + lines.length - 1
      const endColumn = (lines.length === 1 ? Number(startColumn) - 1 : 0) + utf8Length(lines[lines.length - 1])
      await saveMarkdown(element, `${path}:${startLine}:${startColumn}-${endLine}:${endColumn}`, source, prefix, previous, text, true, tag)
    })
  }
  done(result, "markdown")
}

// After any save --------------------------------------------------------------------------------

function remember(element: Element, label: string, run: () => Promise<void>) {
  const key = undoKey(element)
  const entry: HistoryEntry = { key, label: label.replace(/^Undo /, ""), at: new Date(), undone: false, undo: { label, run: async () => {} } }
  entry.undo = { label, run: async () => { undos.delete(key); entry.undone = true; await run() } }
  undos.set(key, entry.undo)
  history.push(entry)
  if (history.length > HISTORY_LIMIT) history.shift()
}

function done(result: { changed?: boolean; file?: string; warning?: string }, kind: SourceKind) {
  if (!result.changed) return
  const entry = history[history.length - 1]
  if (entry && !entry.file && Date.now() - entry.at.getTime() < 10000) entry.file = result.file
  const last = Array.from(undos.values()).pop()
  toast(`Saved ${result.file ?? ""}`.trim(), {
    actions: last ? { Undo: () => last.run().catch(report) } : undefined,
  })
  if (result.warning) toast(result.warning, { timeout: 8000 })
  refresh(kind)
}

export function undo(element: Element) {
  undoFor(element)?.run().catch(report)
}

// Text pieces get their index among text pieces, which survives an edit (the offsets don't).
function indexPieces(pieces: Piece[]) {
  let index = 0
  for (const piece of pieces) if (piece.kind === "text") piece.index = index++
}

const staticParts = (value: string) => value.split(INTERPOLATION).filter((part) => part && !INTERPOLATION.test(part))

// An attribute's value as a stand-in element, so assertRendered can read it.
function attributeNode(element: Element, name: string) {
  const node = document.createElement("span")
  node.textContent = element.getAttribute(name) ?? ""
  return node
}
