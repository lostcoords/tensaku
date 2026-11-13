// A screenshot of what a note points at, taken in the page when the note form opens, so it shows the
// page as the person saw it. modern-screenshot draws the DOM into a canvas: no browser permission,
// no extension. The overlay is left out. Images and fonts it can't fetch (another origin without CORS headers) can be missing.
import { domToCanvas } from "modern-screenshot"

const MARGIN = 40
// Size limits of the canvas the container is drawn on: browsers refuse a side over 16384 or so, and a
// large area costs memory. A container past them (a very long page) is drawn at a lower scale.
const MAX_SIDE = 16000
const MAX_AREA = 40_000_000
// Longest side of the PNG sent to the server.
const MAX_OUTPUT = 1600

const isOverlay = (node: Node) => node instanceof Element && node.hasAttribute("data-tensaku-ui")

// The smallest element that contains rect (viewport coordinates), starting from what is at its centre.
// Something covering that point, such as a sticky header, is skipped when it doesn't contain it.
function containerOf(rect: DOMRect): Element {
  const x = Math.min(Math.max(rect.left + rect.width / 2, 0), innerWidth - 1)
  const y = Math.min(Math.max(rect.top + rect.height / 2, 0), innerHeight - 1)
  let node: Element | null = document.elementsFromPoint(x, y).find((el) => !el.closest("[data-tensaku-ui]")) ?? document.body
  while (node && node !== document.documentElement) {
    const box = node.getBoundingClientRect()
    if (box.left <= rect.left - MARGIN && box.top <= rect.top - MARGIN && box.right >= rect.right + MARGIN && box.bottom >= rect.bottom + MARGIN) break
    node = node.parentElement
  }
  return node ?? document.body
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
