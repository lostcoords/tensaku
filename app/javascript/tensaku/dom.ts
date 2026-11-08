// Reading what producers wrote into the page: Herb's element stamps, Markdown block ranges, and the
// context around an element (partials, Stimulus controller, Turbo Frame).

import { attributeKeyNames, textKeys, type TranslationKey } from "./markers"

export const STAMP = "data-herb-source"
export const MARKDOWN = "data-md-source"
const SOURCE_SELECTOR = `[${STAMP}], [${MARKDOWN}]`

export interface Stamp {
  file: string
  line: number
  column: number
  value: string
}

export function parseStamp(value: string | null | undefined): Stamp | null {
  const match = value?.match(/^(.+):(\d+):(\d+)$/)
  return match ? { file: match[1], line: Number(match[2]), column: Number(match[3]), value: value! } : null
}

export function isUi(node: Node | null): boolean {
  return node instanceof Element && Boolean(node.closest("[data-tensaku-ui]"))
}

// The element a click on `node` means: the nearest element with a source, widened to an ancestor
// marked data-tensaku-group.
export function sourceElement(node: Node | null): Element | null {
  const start = node instanceof Element ? node : node?.parentElement
  if (!start || isUi(start)) return null
  const group = start.closest("[data-tensaku-group]")
  if (group) return group
  return start.closest(SOURCE_SELECTOR)
}

export function stampOf(element: Element): Stamp | null {
  return parseStamp(element.getAttribute(STAMP))
}

// The nearest stamped element, itself or an ancestor. Elements Herb can't stamp (helper output,
// JavaScript-built DOM) are placed through it.
export function nearestStamp(element: Element): Stamp | null {
  return parseStamp(element.closest(`[${STAMP}]`)?.getAttribute(STAMP))
}

export function copiesOf(element: Element): number {
  const value = element.getAttribute(STAMP)
  return value ? document.querySelectorAll(`[${STAMP}="${CSS.escape(value)}"]`).length : 1
}

export function partialChain(element: Element): string[] {
  const files: string[] = []
  for (let node: Element | null = element; node; node = node.parentElement) {
    const stamp = parseStamp(node.getAttribute(STAMP))
    if (stamp && files[files.length - 1] !== stamp.file) files.push(stamp.file)
  }
  return files.filter((file, index) => files.indexOf(file) === index)
}

export function contextOf(element: Element) {
  return {
    partials: partialChain(element),
    controller: element.closest("[data-controller]")?.getAttribute("data-controller") ?? undefined,
    frame: element.closest("turbo-frame")?.id ?? undefined,
  }
}

export function tagLabel(element: Element): string {
  const tag = element.tagName.toLowerCase()
  if (element.id) return `${tag}#${element.id}`
  const first = Array.from(element.classList).find((name) => !name.startsWith("tensaku"))
  return first ? `${tag}.${first}` : tag
}

export function visibleText(element: Element, limit = 120): string {
  const text = (element instanceof HTMLElement ? element.innerText : element.textContent ?? "").replace(/\s+/g, " ").trim()
  return text.length > limit ? text.slice(0, limit - 1) + "…" : text
}

// Direct text of an element (outside child elements, debug spans count as the element's own).
export function hasOwnText(element: Element): boolean {
  for (const node of Array.from(element.childNodes)) {
    if (node.nodeType === Node.TEXT_NODE && node.textContent!.trim()) return true
  }
  return false
}

export function markdownTag(element: Element): string {
  return element.tagName.toLowerCase()
}

const MARKDOWN_EDITABLE = new Set(["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote"])
const ATTRIBUTES = ["alt", "title", "placeholder", "aria-label", "value"]

// The server's answer to /editable: whether a stamp's element has text written in its template.
// Text that all comes from Ruby (<%= %>) has nothing to edit. Stamps not asked about yet count as
// editable, so Alt-click works before edit mode has asked.
export const templateText = new Map<string, boolean>()

export type EditKind = "translation" | "markdown" | "template" | "attributes" | null

// What Alt-click (or a click in edit mode) edits. A translation wins over the template, since the
// template only holds the t() call; Markdown blocks come from their producer's source.
export function editKind(element: Element): EditKind {
  if (translationOf(element)) return "translation"
  if (element.hasAttribute(MARKDOWN) && MARKDOWN_EDITABLE.has(markdownTag(element))) return "markdown"
  if (element.hasAttribute(STAMP) && hasOwnText(element) && templateText.get(element.getAttribute(STAMP)!) !== false) return "template"
  if (editableAttributes(element).length) return "attributes"
  return null
}

export function translationOf(element: Element): TranslationKey | null {
  const keys = textKeys(element)
  if (!keys.length) return null
  // The element's text has to be mostly that translation, or editing it would surprise.
  const own = keys[0].node.data.trim()
  const all = (element.textContent ?? "").replace(/\s+/g, " ").trim()
  return own && all.length <= own.length * 2 + 20 ? keys[0].key : null
}

export function editableAttributes(element: Element): string[] {
  const names = ATTRIBUTES.filter((name) => element.hasAttribute(name))
    .filter((name) => name !== "value" || element.matches("button, input[type=submit], input[type=button], input[type=reset]"))
  const fromStamp = element.hasAttribute(STAMP) ? names : []
  return Array.from(new Set([...fromStamp, ...attributeKeyNames(element).filter((name) => ATTRIBUTES.includes(name))]))
}

export function documentRect(element: Element): DOMRect {
  const rect = element.getBoundingClientRect()
  return new DOMRect(rect.left + scrollX, rect.top + scrollY, rect.width, rect.height)
}

// Block elements span the whole line; what a person sees and drags over is their content.
export function contentRect(element: Element): DOMRect {
  const outer = documentRect(element)
  const range = document.createRange()
  range.selectNodeContents(element)
  const inner = range.getBoundingClientRect()
  if (!inner.width || !inner.height) return outer
  const left = Math.max(outer.left, inner.left + scrollX)
  const top = Math.max(outer.top, inner.top + scrollY)
  return new DOMRect(left, top, Math.min(outer.right, inner.right + scrollX) - left, Math.min(outer.bottom, inner.bottom + scrollY) - top)
}

export function utf8Length(text: string): number {
  return new TextEncoder().encode(text).length
}
