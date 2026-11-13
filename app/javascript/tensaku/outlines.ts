// Edit mode outlines every element whose text can be edited here. It asks the server once which stamped
// elements have template text, and draws after the answer, so text that comes from Ruby is never
// outlined.

import { api } from "./api"
import { documentRect, editKind, hasOwnText, isUi, MARKDOWN, STAMP, templateText } from "./dom"
import { mode } from "./mode"
import { box } from "./ui"

const EDITABLE_BATCH = 5000
let outlines: HTMLElement[] = []
let asking = false

function editableElements(): Element[] {
  const elements = new Set<Element>()
  document.body.querySelectorAll(`[${STAMP}], [${MARKDOWN}], *`).forEach((element) => {
    if (isUi(element) || !(element as HTMLElement).offsetParent && getComputedStyle(element).position !== "fixed") return
    if (editKind(element)) elements.add(element)
  })
  return Array.from(elements)
}

// Draws the outlines again in edit mode, and removes them in any other.
export function drawOutlines() {
  outlines.forEach((b) => b.remove())
  outlines = []
  if (mode() !== "edit") return
  const elements = editableElements()
  const unknown = Array.from(new Set(elements
    .filter((element) => element.hasAttribute(STAMP) && hasOwnText(element))
    .map((element) => element.getAttribute(STAMP)!)
    .filter((stamp) => !templateText.has(stamp)))).slice(0, EDITABLE_BATCH)
  if (unknown.length) {
    if (asking) return
    asking = true
    api<{ editable: Record<string, boolean> }>("POST", "/editable", { stamps: unknown })
      .then(({ editable }) => unknown.forEach((stamp) => templateText.set(stamp, editable[stamp] ?? false)))
      // Without an answer, outline them all.
      .catch(() => unknown.forEach((stamp) => templateText.set(stamp, true)))
      .finally(() => { asking = false; drawOutlines() })
    return
  }
  for (const element of elements) outlines.push(...box(documentRect(element), "edit"))
}
