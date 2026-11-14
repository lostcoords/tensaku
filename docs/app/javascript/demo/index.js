// The landing page's demo: Tensaku's real overlay (tensaku.js, the same file the gem injects)
// running against DemoServer instead of a Rails app. Only the landing page loads this module.

import data from "demo/data"
import { showNote } from "demo/card"
import { renderCode } from "demo/highlight"
import { playHero } from "demo/hero"
import { DemoServer } from "demo/server"

const ROOT = "/__tensaku"

function start() {
  const demo = document.querySelector("[data-demo]")
  if (!demo || window.__tensakuDemo) return
  document.addEventListener("click", (event) => { if (event.target.closest("[data-demo-try]")) openPanel() })
  // In development the real Tensaku is on the page already, editing the real file.
  if (document.querySelector('meta[name="tensaku"]')) {
    highlightLive(demo)
    playHero()
    return
  }
  window.__tensakuDemo = true

  // The page as Herb rendered it in development, with the stamps Tensaku reads.
  const server = new DemoServer()
  demo.innerHTML = data.html
  demo.querySelectorAll("[data-demo-source]").forEach((element) => {
    element.setAttribute("data-herb-source", element.getAttribute("data-demo-source"))
    element.removeAttribute("data-demo-source")
  })

  // The source window belongs to the demo, not to the page: the overlay leaves it alone, even in
  // select mode.
  demo.querySelectorAll("[data-demo-chrome]").forEach((element) => element.setAttribute("data-tensaku-ui", ""))

  const meta = document.createElement("meta")
  meta.name = "tensaku"
  Object.assign(meta.dataset, { tensakuRequest: "GET", tensakuToken: "demo", tensakuRoot: ROOT })
  document.head.append(meta)

  routeFetch(server)
  const code = demo.querySelector("[data-demo-source-code]")
  const firstLine = Number(code.dataset.firstLine)
  const lineCount = code.textContent.split("\n").length
  renderCode(code, code.textContent, { firstLine })
  server.onChange((kind) => {
    if (kind === "note") showNote(server.notes.at(-1))
    if (kind !== "source") return
    renderExcerpt(code, server, firstLine, lineCount)
  })

  const script = document.createElement("script")
  script.src = demo.dataset.demoOverlay
  script.dataset.tensakuUi = ""
  document.body.append(script)
  demo.setAttribute("data-demo-ready", "")
  playHero()
}

// Opens the overlay's toolbar in select mode, so hovering shows where each element comes from and a click opens its menu.
// The overlay may still be loading on an early click.
function openPanel(tries = 50) {
  const overlay = document.querySelector("tensaku-overlay")?.shadowRoot
  const corner = overlay?.querySelector(".corner")
  if (!corner) {
    if (tries) setTimeout(() => openPanel(tries - 1), 100)
    return
  }
  if (corner.getAttribute("aria-expanded") !== "true") corner.click()
  const select = overlay.querySelector(".toolbar button[aria-label='Select']")
  if (select?.getAttribute("aria-pressed") !== "true") select?.click()
}

// In development the server renders the excerpt as plain text, and again after each edit's morph.
function highlightLive(demo) {
  const code = demo.querySelector("[data-demo-source-code]")
  const firstLine = Number(code.dataset.firstLine)
  const highlight = () => { if (!code.querySelector(".demo-code__line")) renderCode(code, code.textContent, { firstLine }) }
  highlight()
  new MutationObserver(highlight).observe(code, { childList: true })
}

// The same lines of the file as it is now, with the last change marked.
function renderExcerpt(code, server, firstLine, lineCount) {
  const lines = server.source.split("\n")
  const offset = lines.slice(0, firstLine - 1).join("\n").length + 1
  const { start, end } = server.lastChange
  renderCode(code, lines.slice(firstLine - 1, firstLine - 1 + lineCount).join("\n"), { firstLine, change: { start: start - offset, end: end - offset } })
}

// The overlay calls fetch for its endpoints, and fetches the page again after a save to morph it.
// Both are answered here; nothing leaves the browser.
function routeFetch(server) {
  const original = window.fetch.bind(window)
  window.fetch = async (input, init = {}) => {
    const url = new URL(typeof input === "string" ? input : input.url, location.href)
    if (url.origin === location.origin && url.pathname.startsWith(ROOT + "/")) {
      const method = (init.method ?? "GET").toUpperCase()
      const body = init.body ? JSON.parse(init.body) : {}
      const path = new URL(url.pathname.slice(ROOT.length) + url.search, location.origin)
      const [status, payload] = server.handle(method, path, body)
      const text = typeof payload === "string" ? payload : JSON.stringify(payload)
      const type = typeof payload === "string" ? "text/markdown" : "application/json"
      await new Promise((resolve) => setTimeout(resolve, 120))
      return new Response(text, { status, headers: { "content-type": type } })
    }
    if (new Headers(init.headers).get("X-Tensaku-Refresh")) {
      // The page as it is now: the stand-in already changed the text, so the morph keeps it. Without
      // the overlay element, which a server's page never contains. The source window stays: the
      // morph keeps overlay UI as it is, and pairs the elements around it by position.
      const page = document.documentElement.cloneNode(true)
      page.querySelectorAll("tensaku-overlay").forEach((element) => element.remove())
      return new Response("<!DOCTYPE html>" + page.outerHTML, { headers: { "content-type": "text/html" } })
    }
    return original(input, init)
  }
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start)
else start()
