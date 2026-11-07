// Updating the page after a save (PLAN decision 5), in layers:
//   1. right away, every node from the same source whose text equals the old text;
//   2. then fetch the URL again and morph the page with idiomorph (GET pages only);
//   3. pages reached by a POST can't be fetched again: keep step 1 and say "reload to check";
//   4. when Herb's dev server is running it patches template changes itself, so step 2 is skipped.

import { Idiomorph } from "idiomorph"
import { meta } from "./api"
import { toast } from "./ui"

export type SourceKind = "template" | "translation" | "markdown"

const listeners: (() => void)[] = []
export function onRefresh(listener: () => void) {
  listeners.push(listener)
}

function permanent(node: Node) {
  return node instanceof Element && (node.hasAttribute("data-turbo-permanent") || node.hasAttribute("data-tensaku-permanent") || node.hasAttribute("data-tensaku-ui"))
}

export function herbDevServer(): boolean {
  return Boolean(document.querySelector('meta[name="herb-dev-server-port"]'))
}

// Step 1: replace text in text nodes, comparing whitespace-collapsed text.
export function replaceText(nodes: Text[], from: string, to: string) {
  const normal = (text: string) => text.replace(/\s+/g, " ").trim()
  const target = normal(from)
  if (!target) return
  for (const node of nodes) {
    if (normal(node.data) === target) {
      const lead = node.data.match(/^\s*/)![0]
      const trail = node.data.match(/\s*$/)![0]
      node.data = lead + to.trim() + trail
    } else if (node.data.includes(from) && from.trim()) {
      node.data = node.data.replace(from, to)
    }
  }
}

export async function refresh(kind: SourceKind) {
  if (meta().method !== "GET") {
    toast("Saved. This page came from a form submission, so reload to check it.", { timeout: 7000 })
    return
  }
  if (kind === "template" && herbDevServer()) return

  try {
    const response = await fetch(location.href, { headers: { Accept: "text/html", "X-Tensaku-Refresh": "1" }, credentials: "same-origin" })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const html = await response.text()
    const next = new DOMParser().parseFromString(html, "text/html")
    morph(next)
  } catch (error) {
    toast(`Saved, but refreshing the page failed (${(error as Error).message}). Reload to check.`, { error: true })
  }
}

function morph(next: Document) {
  const lazyFrames = Array.from(document.querySelectorAll("turbo-frame[src]"))
  Idiomorph.morph(document.body, next.body, {
    morphStyle: "outerHTML",
    ignoreActiveValue: true,
    restoreFocus: true,
    callbacks: {
      beforeNodeMorphed: (oldNode) => !permanent(oldNode),
      beforeNodeRemoved: (node) => !permanent(node),
    },
  })
  if (next.title) document.title = next.title
  // Frames that loaded their content lazily come back from the server with their placeholder.
  for (const frame of lazyFrames) {
    if (frame.isConnected && typeof (frame as any).reload === "function" && !frame.hasAttribute("complete")) (frame as any).reload()
  }
  listeners.forEach((listener) => listener())
}
