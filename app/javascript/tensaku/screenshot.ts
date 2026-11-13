// A screenshot of what a note points at, taken in the page when the note form opens, so it shows the
// page as the person saw it. modern-screenshot draws the DOM into a canvas: no browser permission,
// no extension. The overlay is left out. An image from another origin without CORS headers is left out
// too (checked in Chromium and WebKit); same-origin images and data URLs show.
import { domToCanvas } from "modern-screenshot"

const MARGIN = 40
// Size limits of the canvas the container is drawn on: browsers refuse a side over 16384 or so, and a
// large area costs memory. A container past them (a very long page) is drawn at a lower scale.
const MAX_SIDE = 16000
const MAX_AREA = 40_000_000
// Longest side of the PNG sent to the server.
const MAX_OUTPUT = 1600

const isOverlay = (node: Node) => node instanceof Element && node.hasAttribute("data-tensaku-ui")

// Drawing copies the container's whole subtree, so the cost grows with its size: a container with
// more elements than this is drawn without the margin (see containerOf).
const MAX_NODES = 2000

// The element to draw for rect (viewport coordinates): the smallest one that contains rect plus a
// margin, starting from what is at its centre. When that one has more than MAX_NODES elements (a long
// page), the smallest element that contains rect itself, so a note on one row of a big table costs
// that row, not the table. Something covering the point, such as a sticky header, is skipped when it
// doesn't contain it.
function containerOf(rect: DOMRect): Element {
  const x = Math.min(Math.max(rect.left + rect.width / 2, 0), innerWidth - 1)
  const y = Math.min(Math.max(rect.top + rect.height / 2, 0), innerHeight - 1)
  const contains = (box: DOMRect, margin: number) =>
    box.left <= rect.left - margin && box.top <= rect.top - margin && box.right >= rect.right + margin && box.bottom >= rect.bottom + margin
  let node: Element | null = document.elementsFromPoint(x, y).find((el) => !el.closest("[data-tensaku-ui]")) ?? document.body
  let tight: Element | null = null
  while (node && node !== document.documentElement) {
    const box = node.getBoundingClientRect()
    tight ??= contains(box, -0.5) ? node : null
    if (tight && node.getElementsByTagName("*").length > MAX_NODES) return tight
    if (contains(box, MARGIN)) return node
    node = node.parentElement
  }
  return tight ?? document.body
}

// A PNG data URL of area (document coordinates, as the note form gets them) and a margin around it,
// or null when the page can't be drawn.
export async function capture(area: DOMRect): Promise<string | null> {
  try {
    const rect = new DOMRect(area.x - scrollX, area.y - scrollY, area.width, area.height)
    const node = containerOf(rect)
    const box = node.getBoundingClientRect()
    const scale = Math.min(devicePixelRatio || 1, 2, MAX_SIDE / Math.max(box.width, box.height, 1), Math.sqrt(MAX_AREA / Math.max(box.width * box.height, 1)))
    const canvas = await domToCanvas(node, { scale, filter: (n) => !isOverlay(n), timeout: 3000, backgroundColor: getComputedStyle(document.body).backgroundColor || "#fff" })
    const left = Math.max(rect.left - MARGIN, box.left)
    const top = Math.max(rect.top - MARGIN, box.top)
    const width = Math.min(rect.right + MARGIN, box.right) - left
    const height = Math.min(rect.bottom + MARGIN, box.bottom) - top
    if (width < 1 || height < 1) return null
    const shrink = Math.min(1, MAX_OUTPUT / (Math.max(width, height) * scale))
    const out = document.createElement("canvas")
    out.width = Math.round(width * scale * shrink)
    out.height = Math.round(height * scale * shrink)
    out.getContext("2d")!.drawImage(canvas, (left - box.left) * scale, (top - box.top) * scale, width * scale, height * scale, 0, 0, out.width, out.height)
    return out.toDataURL("image/png")
  } catch {
    return null
  }
}
