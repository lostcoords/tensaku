// Where a note points on the page, both ways: the targets a new note records for an element, and the
// element, rectangle or phrase an existing note's targets point at now.

import { contentRect, contextOf, documentRect, MARKDOWN, nearestStamp, STAMP, tagLabel, translationOf, visibleText } from "./dom"
import { textKeys } from "./markers"
import type { Note, Target } from "./notes"

// The element's own classes, so an agent can tell why it looks the way it does.
const classesOf = (element: Element) => Array.from(element.classList).filter((name) => !name.startsWith("tensaku")).slice(0, 12)

export function targetsFor(element: Element, selectedText?: string): Target[] {
  const block = element.closest(`[${MARKDOWN}]`)
  const stamped = element.closest(`[${STAMP}]`)
  // A Markdown block inside the nearest stamped element (Kiln renders pages into a layout) points at
  // the source more precisely than that element, so it replaces it.
  if (block && (!stamped || stamped.contains(block))) {
    return [{
      kind: "markdown",
      md: block.getAttribute(MARKDOWN) ?? undefined,
      text: selectedText || visibleText(element, 300),
      tag: tagLabel(element),
      context: contextOf(element),
    }]
  }
  const stamp = nearestStamp(element)
  const base: Target = {
    kind: selectedText ? "text" : "element",
    stamp: stamp?.value,
    text: selectedText || visibleText(element, 300),
    tag: tagLabel(element),
    classes: classesOf(element),
    context: contextOf(element),
  }
  const targets = [base]
  const key = translationOf(element) ?? textKeys(element)[0]?.key
  if (key) targets.push({ kind: "translation", key: key.key, locale: key.locale, text: visibleText(element, 300) })
  const md = element.closest(`[${MARKDOWN}]`)?.getAttribute(MARKDOWN)
  if (md) targets.push({ kind: "markdown", md, text: visibleText(element, 300), tag: tagLabel(element) })
  return targets
}

// The elements an area covers: stamped elements mostly inside the rectangle, outermost first, or the
// innermost element under its center when nothing fits.
export function elementsInArea(rect: DOMRect): Element[] {
  const candidates = Array.from(document.querySelectorAll(`[${STAMP}], [${MARKDOWN}]`)).filter((element) => {
    if (element === document.body || element.closest("[data-tensaku-ui]")) return false
    const box = contentRect(element)
    if (!box.width || !box.height) return false
    const overlap = Math.max(0, Math.min(box.right, rect.right) - Math.max(box.left, rect.left)) * Math.max(0, Math.min(box.bottom, rect.bottom) - Math.max(box.top, rect.top))
    return overlap / (box.width * box.height) >= 0.5
  })
  const outermost = candidates.filter((element) => !candidates.some((other) => other !== element && other.contains(element)))
  if (outermost.length) return outermost.slice(0, 20)
  const center = document.elementFromPoint(rect.left + rect.width / 2 - scrollX, rect.top + rect.height / 2 - scrollY)
  const fallback = center?.closest(`[${STAMP}], [${MARKDOWN}]`)
  return fallback ? [fallback] : []
}

// The selected text a "text" note is about, found again in its element.
export function phraseRects(note: Note): DOMRect[] {
  const target = note.targets.find((t) => t.kind === "text" && t.text && t.stamp)
  const element = target && targetElement(target)
  if (!target || !element?.textContent?.includes(target.text!)) return []
  const nodes: Text[] = []
  const starts: number[] = []
  let all = ""
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT)
  while (walker.nextNode()) {
    const node = walker.currentNode as Text
    starts.push(all.length)
    nodes.push(node)
    all += node.data
  }
  const at = all.indexOf(target.text!)
  if (at < 0) return []
  const end = at + target.text!.length
  const lastIndex = (test: (start: number) => boolean) => { for (let i = starts.length - 1; i >= 0; i--) if (test(starts[i])) return i; return 0 }
  const first = lastIndex((start) => start <= at)
  const last = lastIndex((start) => start < end)
  const range = document.createRange()
  range.setStart(nodes[first], at - starts[first])
  range.setEnd(nodes[last], end - starts[last])
  return Array.from(range.getClientRects()).filter((r) => r.width > 0).map((r) => new DOMRect(r.left + scrollX, r.top + scrollY, r.width, r.height))
}

// The note's area, or the box of the first target still on the page.
export function anchorFor(note: Note): DOMRect | null {
  if (note.rect) return new DOMRect(note.rect.x, note.rect.y, note.rect.width, note.rect.height)
  for (const target of note.targets) {
    const element = targetElement(target)
    if (element) return contentRect(element)
  }
  return null
}

// The point a note was written at, on its element as it is laid out now.
export function pointFor(note: Note): DOMRect | null {
  const target = note.targets.find((t) => t.point)
  const element = target && targetElement(target)
  if (!target?.point || !element) return null
  const rect = documentRect(element)
  return new DOMRect(rect.x + target.point[0] * rect.width, rect.y + target.point[1] * rect.height, 0, 0)
}

// A stamp is shared by every copy of an element a loop renders; the note belongs to the copy whose
// text it was written about. A stamp is also a line and a column, which go stale when the file changes:
// the element is then looked for by its tag and text elsewhere in the same file. With no match the note
// stays on an element of the same tag at its old position, whose text may have been edited, or nowhere.
function targetElement(target: Target): Element | null {
  const attribute = target.stamp ? STAMP : target.md ? MARKDOWN : null
  const value = target.stamp ?? target.md
  if (!attribute || !value) return null
  const elements = Array.from(document.querySelectorAll(`[${attribute}="${CSS.escape(value)}"]`))
  if (!target.text) return elements[0] ?? null

  const text = target.text.replace(/…$/, "")
  const written = (candidates: Element[]) =>
    candidates.find((element) => visibleText(element, 300) === target.text)
    ?? candidates.find((element) => visibleText(element, 300).startsWith(text))
    ?? candidates.find((element) => target.kind === "text" && element.textContent?.includes(text))
  const here = written(elements)
  if (here) return here

  const tag = target.tag?.split(/[.#]/)[0]
  const sameTag = (element: Element) => !tag || element.tagName.toLowerCase() === tag
  const file = value.match(/^(.+?):\d+/)?.[1]
  const inFile = file ? Array.from(document.querySelectorAll(`[${attribute}^="${CSS.escape(file)}:"]`)).filter(sameTag) : []
  return written(inFile) ?? elements.find(sameTag) ?? null
}
