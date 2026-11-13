// Editing text in place. The editor shows the source's static text as editable fields. Ruby output and
// translation interpolations are locked chips. Child elements show as they look on the page: a line
// break breaks, an element's text keeps its style and opens its own editor on a click, and an element
// without text is a small mark.

import { diffRows, type Diff } from "./diff"
import { api, ApiError, query } from "./api"
import { attributeKey, nodesForKey, elementsWithAttributeKey, type TranslationKey } from "./markers"
import { contentRect, copiesOf, editableAttributes, MARKDOWN, stampOf, STAMP, translationOf, utf8Length, editKind, visibleText } from "./dom"
import { refresh, replaceText, type SourceKind } from "./refresh"
import { activeInShadow, div, h, layer, place, toast } from "./ui"

interface TextPiece { kind: "text"; start: number; end: number; raw: string; text: string; index?: number }
interface ElementPiece { kind: "element"; tag: string; label: string; stamp?: string | null }
type Piece = TextPiece | { kind: "ruby"; code: string } | ElementPiece | { kind: "hidden" }
interface Attribute { name: string; quote: string | null; pieces: Piece[] }
interface Description { file: string; stamp: string; range: string; tag: string; helper: boolean; editable: boolean; pieces: Piece[]; attributes: Attribute[] }
interface LocaleEntry { file?: string; line?: number; value: string | null; editable: boolean }
interface MarkdownDescription { file: string; range: string; editable: boolean; prefix: string; text: string; original: string }

// Undo and redo ------------------------------------------------------------------------------
//
// Every save is an entry: what changed, from what to what, as data, so the stacks survive a reload
// (sessionStorage, per tab). Undo reverts the latest save, or a chosen one, and moves it to the redo
// stack; redo applies the latest undone edit again; a new save clears the redo stack. Each step checks
// that the source still holds the text it expects, like any save.

type Op =
  | { kind: "template"; stamp: string; changes: { index: number; from: string; to: string }[] }
  | { kind: "attribute"; stamp: string; changes: { name: string; index: number; from: string; to: string }[] }
  // Every locale saved from one translation editor, undone and redone together.
  | { kind: "translation"; key: string; changes: { locale: string; from: string; to: string }[] }
  // range covers the block as it reads now: after `to` when done, after `from` when undone.
  | { kind: "markdown"; range: string; prefix: string; from: string; to: string; tag?: string }
export interface Entry { id: number; label: string; key: string | null; file?: string; at: string; op: Op }

const HISTORY_LIMIT = 50
const HISTORY_KEY = "tensaku:history"
let done: Entry[] = []
let undone: Entry[] = []
try {
  const saved = JSON.parse(sessionStorage.getItem(HISTORY_KEY) ?? "null")
  if (saved && Array.isArray(saved.done) && Array.isArray(saved.undone)) ({ done, undone } = saved)
} catch {
  // Blocked storage: the stacks start empty and last until the page is left.
}
function persist() {
  try {
    sessionStorage.setItem(HISTORY_KEY, JSON.stringify({ done, undone }))
  } catch {
    // Blocked storage: the stacks still work on this page.
  }
}
const nextId = () => Math.max(0, ...done.map((entry) => entry.id), ...undone.map((entry) => entry.id)) + 1

function record(element: Element | null, label: string, op: Op, file?: string): Entry {
  const entry: Entry = { id: nextId(), label, key: element ? undoKey(element) : null, file, at: new Date().toISOString(), op }
  done.push(entry)
  if (done.length > HISTORY_LIMIT) done.shift()
  undone = []
  persist()
  return entry
}

// The saves for the history popover, newest first: those that can be undone, and those that can be
// redone (only the latest of these with Redo).
export function editHistory() {
  return { done: done.slice().reverse(), undone: undone.slice().reverse() }
}

export const canUndo = () => done.length > 0
export const canRedo = () => undone.length > 0

// Reverts entry, or the latest save, and puts it on the redo stack.
export async function undo(entry: Entry | undefined = done[done.length - 1]) {
  if (!entry || !done.includes(entry)) return toast("That edit was undone already.")
  try {
    const result = await apply(entry.op, true)
    done = done.filter((item) => item !== entry)
    undone.push(entry)
    persist()
    finish(result, sourceKind(entry.op), `Undid ${entry.label}`, { Redo: () => redo(entry) })
  } catch (error) {
    report(error)
  }
}

export async function redo(entry: Entry | undefined = undone[undone.length - 1]) {
  if (!entry || undone[undone.length - 1] !== entry) return toast("Only the latest undone edit can be redone.")
  try {
    const result = await apply(entry.op, false)
    undone.pop()
    done.push(entry)
    persist()
    finish(result, sourceKind(entry.op), `Redid ${entry.label}`, { Undo: () => undo(entry) })
  } catch (error) {
    report(error)
  }
}

const sourceKind = (op: Op): SourceKind => op.kind === "attribute" ? "template" : op.kind

// The latest save on element that can still be undone.
export function undoFor(element: Element): Entry | undefined {
  const key = undoKey(element)
  return key ? done.slice().reverse().find((entry) => entry.key === key) : undefined
}

// Writes op's `from` back over `to` (undo), or `to` over `from` (redo), after checking the source
// still reads what the step expects.
async function apply(op: Op, reverse: boolean): Promise<SaveResult> {
  const verb = reverse ? "undone" : "redone"
  const stale = (what: string) => new ApiError(`The ${what} changed since the edit, so it can't be ${verb} here.`, 409, true)
  if (op.kind === "template") {
    const fresh = await api<Description>("GET", "/source" + query({ stamp: op.stamp }))
    const texts = fresh.pieces.filter((p): p is TextPiece => p.kind === "text")
    const edits = op.changes.map(({ index, from, to }) => {
      const [current, target] = reverse ? [to, from] : [from, to]
      const now = texts[index]
      if (!now || now.text !== current) throw stale("text")
      return { piece: now, current, target }
    })
    const result = await api<SaveResult>("POST", "/text", { stamp: op.stamp, edits: edits.map(({ piece, target }) => ({ start: piece.start, end: piece.end, original: piece.raw, text: target })) })
    const nodes = textNodesOf(op.stamp)
    edits.forEach(({ current, target }) => replaceText(nodes, current, target))
    return result
  }
  if (op.kind === "attribute") {
    let result: SaveResult = {}
    for (const { name, index, from, to } of op.changes) {
      const [current, target] = reverse ? [to, from] : [from, to]
      const fresh = await api<Description>("GET", "/source" + query({ stamp: op.stamp }))
      const now = fresh.attributes.find((a) => a.name === name)?.pieces.filter((p): p is TextPiece => p.kind === "text")[index]
      if (!now || now.text !== current) throw stale("attribute")
      result = await api<SaveResult>("POST", "/attribute", { stamp: op.stamp, name, start: now.start, end: now.end, original: now.raw, text: target })
      document.querySelectorAll(`[${STAMP}="${CSS.escape(op.stamp)}"]`).forEach((el) => {
        const value = el.getAttribute(name)
        if (value !== null) el.setAttribute(name, value.replace(current, target))
      })
    }
    return { ...result, changed: true }
  }
  if (op.kind === "translation") {
    let result: SaveResult = {}
    for (const { locale, from, to } of op.changes) {
      const [current, target] = reverse ? [to, from] : [from, to]
      const saved = await api<SaveResult>("POST", "/translation", { locale, key: op.key, original: current, text: target })
      result = { ...saved, file: result.file ?? saved.file, changed: true }
      showTranslation({ locale, key: op.key }, current, target)
    }
    return result
  }
  const [current, target] = reverse ? [op.to, op.from] : [op.from, op.to]
  const result = await api<SaveResult>("POST", "/markdown", { range: op.range, original: op.prefix + current, text: target, tag: op.tag })
  op.range = rangeAfter(op.range, op.prefix + target)
  return result
}

// A Markdown block's range once its source is text: same start, the end moved to where text ends.
function rangeAfter(range: string, text: string) {
  const [, path, startLine, startColumn] = range.match(/^(.+):(\d+):(\d+)-/)!
  const lines = text.split("\n")
  const endLine = Number(startLine) + lines.length - 1
  const endColumn = (lines.length === 1 ? Number(startColumn) - 1 : 0) + utf8Length(lines[lines.length - 1])
  return `${path}:${startLine}:${startColumn}-${endLine}:${endColumn}`
}

const textNodesOf = (stamp: string) => Array.from(document.querySelectorAll(`[${STAMP}="${CSS.escape(stamp)}"]`)).flatMap((el) =>
  Array.from(el.childNodes).filter((node): node is Text => node.nodeType === Node.TEXT_NODE))

function showTranslation(key: TranslationKey, from: string, to: string) {
  if (INTERPOLATION.test(from)) return
  replaceText(nodesForKey(key), from, to)
  elementsWithAttributeKey(key).forEach(({ element: el, name }) => { if (el.getAttribute(name) === from) el.setAttribute(name, to) })
}

let open: { element: HTMLElement; save: () => Promise<void>; close: () => void } | null = null

// The element's source position, so the element menu can undo its latest save, or null when it has
// none (a translated attribute on an element without a stamp).
function undoKey(element: Element): string | null {
  const translation = translationOf(element)
  return element.getAttribute(STAMP) ?? element.getAttribute(MARKDOWN) ?? (translation ? `${translation.locale}.${translation.key}` : null)
}

// Enter that confirms an IME composition (Japanese, Chinese, Korean input) must not save or insert.
const composing = (event: KeyboardEvent) => event.isComposing || event.keyCode === 229

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
  if (!multiline) span.addEventListener("keydown", (event) => { if (event.key === "Enter" && event.shiftKey && !composing(event)) event.preventDefault() })
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
    div("bar", h("span", {}, status, warning ? h("strong", { className: "ink-warning" }, ` · ${warning}`) : null),
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
    if (event.key !== "Enter" || composing(event) || !activeInShadow()?.classList.contains("editable")) return
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

const NESTED_STYLES = ["fontFamily", "fontSize", "fontStyle", "fontWeight", "letterSpacing", "textTransform", "color"] as const

// A child element, as it looks on the page. Returns null for one that takes no space in the text
// around it: hidden, or positioned out of the flow like a decorative underline.
function nestedElement(piece: ElementPiece, host: Element | undefined, unchanged: () => boolean): Node | null {
  if (piece.tag === "br" || piece.tag.startsWith("br.") || piece.tag.startsWith("br#")) return document.createElement("br")
  const child = piece.stamp ? host?.querySelector(`[${STAMP}="${CSS.escape(piece.stamp)}"]`) : null
  const computed = child ? getComputedStyle(child) : null
  if (computed && (computed.display === "none" || computed.position === "absolute" || computed.position === "fixed")) return null
  const text = child ? visibleText(child, 80) : piece.label
  if (!text) return h("span", { className: "chip mark", title: `<${piece.tag}>`, contenteditable: "false" })

  const span = h("span", { className: "nested", contenteditable: "false" }, text)
  if (computed) {
    NESTED_STYLES.forEach((name) => { span.style[name] = computed[name] })
    if (!computed.display.startsWith("inline")) span.style.display = "block"
  }
  if (child && editKind(child)) {
    span.classList.add("link")
    span.title = "Edit this element on its own"
    // With unsaved changes, clicking away saves them, as a click anywhere outside the fields does.
    span.addEventListener("click", () => { if (unchanged()) edit(child) })
  }
  return span
}

function pieceSurface(pieces: Piece[], host?: Element) {
  const surface = div("")
  const fields: { span: HTMLElement; piece: TextPiece }[] = []
  const unchanged = () => fields.every(({ span, piece }) => valueOf(span) === piece.text)
  for (const piece of pieces) {
    if (piece.kind === "text") {
      // Whitespace between elements isn't text anyone edits. A space after a line break would only
      // push the next line out of place.
      if (!piece.text.trim()) {
        if (surface.lastChild && surface.lastChild.nodeName !== "BR") surface.append(" ")
        continue
      }
      const span = field(piece.text)
      fields.push({ span, piece })
      surface.append(span)
    } else if (piece.kind === "ruby") surface.append(chip(piece.code.length > 30 ? piece.code.slice(0, 29) + "…" : piece.code, piece.code))
    else if (piece.kind === "element") {
      const node = nestedElement(piece, host, unchanged)
      if (node) surface.append(node)
    }
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
  const { surface, fields } = pieceSurface(info.pieces, element)
  const copies = copiesOf(element)
  frame(element, surface, `${info.file}:${stamp.line}`, async () => {
    const changed = fields.filter(({ span, piece }) => valueOf(span) !== piece.text)
    if (!changed.length) return
    await saveTemplate(element, stamp.value, changed.map(({ span, piece }) => ({ piece, text: valueOf(span) })))
  }, [], copies > 1 ? `this edits all ${copies} copies` : undefined)
}

async function saveTemplate(element: Element, stamp: string, changes: { piece: TextPiece; text: string }[]) {
  const result = await api<SaveResult>("POST", "/text", {
    stamp,
    edits: changes.map(({ piece, text }) => ({ start: piece.start, end: piece.end, original: piece.raw, text })),
  })
  const nodes = textNodesOf(stamp)
  changes.forEach(({ piece, text }) => replaceText(nodes, piece.text, text))
  const entry = result.changed ? record(element, `edit in ${stamp}`, { kind: "template", stamp, changes: changes.map(({ piece, text }) => ({ index: piece.index ?? -1, from: piece.text, to: text })) }, result.file) : undefined
  done_(result, "template", entry)
}

// Attributes -----------------------------------------------------------------------------------

async function editAttributes(element: Element) {
  const stamp = stampOf(element)
  const description = stamp ? await api<Description>("GET", "/source" + query({ stamp: stamp.value })) : null
  const names = editableAttributes(element)
  const rows: Node[] = []
  const savers: (() => Promise<void>)[] = []
  // Template attribute text, across every attribute of the element, saved in one pass at the end.
  const templateFields: { name: string; span: HTMLElement; piece: TextPiece }[] = []

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
        if (text === entry.value) return
        await saveTranslations(element, key, [ { locale: key.locale, from: entry.value!, to: text } ])
        // A retry after a later save fails starts from what is in the file now.
        entry.value = text
      })
      continue
    }
    const attribute = description?.attributes.find((a) => a.name === name)
    if (!attribute || !attribute.pieces.some((p) => p.kind === "text")) continue
    assertRendered(attributeNode(element, name), attribute.pieces.filter((p): p is TextPiece => p.kind === "text").map((p) => p.text))
    const { surface, fields } = pieceSurface(attribute.pieces)
    rows.push(div("attr", h("span", { className: "name" }, name), div("value", surface)))
    fields.forEach(({ span, piece }) => templateFields.push({ name, span, piece }))
  }
  if (templateFields.length) savers.push(() => saveAttributePieces(element, stamp!.value, templateFields))
  if (!rows.length) throw new Error("Nothing here can be edited. Leave a note instead.")

  const surface = div("")
  surface.append(...rows)
  frame(element, surface, description ? `${description.file}:${stamp!.line} attributes` : "attributes", async () => {
    for (const save of savers) await save()
  })
}

// The /attribute endpoint takes one piece at a time, addressed by byte offsets in the file. Pieces are
// sent from the end of the file backwards, so a write never moves the offsets of the pieces still to
// send. A piece that saved is marked as such, so a retry after a failure only sends what is left.
async function saveAttributePieces(element: Element, stamp: string, fields: { name: string; span: HTMLElement; piece: TextPiece }[]) {
  const changed = fields
    .map(({ name, span, piece }) => ({ name, piece, text: valueOf(span) }))
    .filter(({ piece, text }) => text !== piece.text)
    .sort((a, b) => b.piece.start - a.piece.start)
  if (!changed.length) return
  const saved: { name: string; index: number; from: string; to: string }[] = []
  let last: { changed?: boolean; file?: string; warning?: string } = {}
  try {
    for (const { name, piece, text } of changed) {
      last = await api("POST", "/attribute", { stamp, name, start: piece.start, end: piece.end, original: piece.raw, text })
      document.querySelectorAll(`[${STAMP}="${CSS.escape(stamp)}"]`).forEach((el) => {
        const current = el.getAttribute(name)
        if (current !== null) el.setAttribute(name, current.replace(piece.text, text))
      })
      const index = fields.filter((field) => field.name === name).findIndex((field) => field.piece === piece)
      saved.push({ name, index, from: piece.text, to: text })
      piece.text = text
    }
  } finally {
    if (saved.length) {
      const names = Array.from(new Set(saved.map((change) => change.name))).join(", ")
      const entry = record(element, names, { kind: "attribute", stamp, changes: saved }, last.file)
      done_({ ...last, changed: true }, "template", entry)
    }
  }
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
      otherRows.append(div("locale", h("span", { className: "code" }, locale), h("em", { className: "ink-muted" }, other.value === null ? "missing" : `${other.value} (not writable)`)))
    }
  }
  const toggle = others.length
    ? h("button", { className: "link", type: "button", onclick: () => { otherRows.hidden = !otherRows.hidden; toggle!.textContent = otherRows.hidden ? `Other locales (${others.length})` : "Hide other locales" } }, `Other locales (${others.length})`)
    : null
  const extra = toggle ? [div("locale", h("span", { className: "code" }, ""), toggle), otherRows] : []

  frame(element, main.surface, `${key.locale}.${key.key} · ${entry.file}:${entry.line}`, async () => {
    // Each write that succeeds updates what the editor holds as the file's value, so a retry after a
    // later write fails doesn't resend it with an outdated original.
    const sources = [ { locale: key.locale, entry, read: main.read }, ...otherReaders ]
    const changes = sources.flatMap(({ locale, entry, read }) => {
      const to = read()
      return to === entry.value ? [] : [ { locale, from: entry.value!, to, entry } ]
    })
    await saveTranslations(element, key, changes, (change) => { change.entry.value = change.to })
  }, extra)
}

// Saves each locale in turn and records them as one edit, so one undo reverts them all. A failure
// keeps the locales saved before it in the history, and then reports.
async function saveTranslations<T extends { locale: string; from: string; to: string }>(element: Element, key: TranslationKey, changes: T[], onSaved: (change: T) => void = () => {}) {
  const saved: { locale: string; from: string; to: string }[] = []
  let result: SaveResult = {}
  try {
    for (const change of changes) {
      const reply = await api<SaveResult>("POST", "/translation", { locale: change.locale, key: key.key, original: change.from, text: change.to })
      showTranslation({ locale: change.locale, key: key.key }, change.from, change.to)
      onSaved(change)
      if (reply.changed) saved.push({ locale: change.locale, from: change.from, to: change.to })
      result = { ...reply, file: result.file ?? reply.file, changed: result.changed || reply.changed }
    }
  } finally {
    const label = saved.length > 1 ? `${key.key} in ${saved.length} locales` : key.key
    const entry = saved.length ? record(element, label, { kind: "translation", key: key.key, changes: saved }, result.file) : undefined
    if (saved.length) done_(result, "translation", entry)
  }
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
    await saveMarkdown(element, range, info.original, info.prefix, value, info.text, tag)
  })
}

async function saveMarkdown(element: Element, range: string, original: string, prefix: string, text: string, previous: string, tag?: string) {
  const result = await api<SaveResult>("POST", "/markdown", { range, original, text, tag })
  if (!tag?.match(/^[uo]l$/) && !/[*_`\[\]<>#]/.test(previous + text)) replaceText(Array.from(element.childNodes).filter((n): n is Text => n.nodeType === Node.TEXT_NODE), previous, text)
  const entry = result.changed ? record(element, "Markdown edit", { kind: "markdown", range: rangeAfter(range, prefix + text), prefix, from: previous, to: text, tag }, result.file) : undefined
  done_(result, "markdown", entry)
}

// After any save --------------------------------------------------------------------------------

type SaveResult = { changed?: boolean; file?: string; warning?: string; diff?: Diff }

// A save made in the editor: its toast offers Undo while the entry can still be undone.
function done_(result: SaveResult, kind: SourceKind, entry?: Entry) {
  finish(result, kind, "Saved", entry ? { Undo: () => undo(entry) } : undefined)
}

function finish(result: SaveResult, kind: SourceKind, verb: string, actions?: Record<string, () => void>) {
  if (!result.changed) return
  const where = result.diff ? `${result.file}:${result.diff.line}` : result.file ?? ""
  toast(`${verb} ${where}`.trim(), {
    timeout: result.diff ? 8000 : undefined,
    detail: result.diff ? diffRows(result.diff) : undefined,
    actions,
  })
  if (result.warning) toast(result.warning, { timeout: 8000 })
  refresh(kind)
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
