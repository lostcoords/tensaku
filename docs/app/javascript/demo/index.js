// The landing page's demo: Tensaku's real overlay (tensaku.js, the same file the gem injects)
// running against DemoServer instead of a Rails app. Only the landing page loads this module.

import data from "demo/data"
import { DemoServer } from "demo/server"

const ROOT = "/__tensaku"

function start() {
  const demo = document.querySelector("[data-demo]")
  if (!demo || window.__tensakuDemo) return
  // In development the real Tensaku is on the page already, editing the real file.
  if (document.querySelector('meta[name="tensaku"]')) {
    demo.querySelector("[data-demo-static]")?.setAttribute("hidden", "")
    demo.querySelector("[data-demo-live-only]")?.removeAttribute("hidden")
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
  Object.assign(meta.dataset, { tensakuRequest: "GET", tensakuToken: "demo", tensakuRoot: ROOT, tensakuShortcut: "alt+shift+KeyT" })
  document.head.append(meta)

  routeFetch(server)
  const window_ = demo.querySelector("[data-demo-chrome]")
  window_.querySelector("[data-demo-agent-resolve]").addEventListener("click", () => resolveAsAgent(server))
  renderSource(window_, server)
  renderAgent(window_, server)
server.onChange((kind) => {
  renderSource(window_, server)
  renderAgent(window_, server)
  // Show what just changed: the file after an edit, or the notes after a new one.
  if (kind === "source") showTab(window_, "source")
  else if (server.notes.some((note) => note.status === "open")) showTab(window_, "agent")
})

  const script = document.createElement("script")
  script.src = demo.dataset.demoOverlay
  script.dataset.tensakuUi = ""
  document.body.append(script)
  demo.setAttribute("data-demo-ready", "")
}

// lc_tabs owns the tabs; selecting one is a click on it.
function showTab(window_, name) {
  const tab = window_.querySelector(`[role="tab"][data-value="${name}"]`)
  if (tab && tab.getAttribute("aria-selected") !== "true") tab.click()
  // Scrolls the code, not the page, so the changed line is in view.
  const changed = window_.querySelector(".demo-code__line--changed")
  const code = window_.querySelector("[data-demo-source-code]")
  if (name === "source" && changed) requestAnimationFrame(() => code.scrollTo({ top: changed.offsetTop - code.clientHeight / 2, behavior: "smooth" }))
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

function renderSource(window_, server) {
  const target = window_.querySelector("[data-demo-source-code]")
  if (!target) return
  const { start, end } = server.lastChange ?? { start: -1, end: -1 }
  const lines = []
  let offset = 0
  server.source.replace(/\n$/, "").split("\n").forEach((line, index) => {
    const lineStart = offset
    const lineEnd = offset + line.length
    offset = lineEnd + 1
    const changed = start >= 0 && start <= lineEnd && end >= lineStart
    const row = document.createElement("span")
    row.className = "demo-code__line" + (changed ? " demo-code__line--changed" : "")
    const number = document.createElement("span")
    number.className = "demo-code__number"
    number.textContent = index + 1
    const code = document.createElement("span")
    if (changed) {
      const from = Math.max(start, lineStart) - lineStart
      const to = Math.min(end, lineEnd) - lineStart
      const mark = document.createElement("mark")
      mark.textContent = line.slice(from, to)
      code.append(line.slice(0, from), mark, line.slice(to))
    } else {
      code.textContent = line
    }
    row.append(number, code)
    lines.push(row)
  })
  target.replaceChildren(...lines)
}

function renderAgent(window_, server) {
  const target = window_.querySelector("[data-demo-agent]")
  if (!target) return
  const open = server.notes.filter((note) => note.status !== "resolved")
  target.textContent = open.length ? server.markdown(open) : "No open notes yet. Leave one on the page, and it shows up here the way your agent reads it."
  const count = window_.querySelector("[data-demo-count]")
  count.textContent = open.length
  count.hidden = !open.length
  const button = window_.querySelector("[data-demo-agent-resolve]")
  if (button) button.disabled = !open.some((note) => note.status === "open")
}

// What a coding agent does through MCP: start_note (the pin shows it is being worked on), then
// resolve_note with a reply, and the pin turns green.
async function resolveAsAgent(server) {
  const notes = server.notes.filter((n) => n.status === "open")
  server.agentConnected = true
  for (const note of notes) server.updateNote(note.id, { status: "working", agent: "Your agent" })
  // The overlay reloads its notes on Turbo's page load.
  document.dispatchEvent(new Event("turbo:load"))
  await new Promise((resolve) => setTimeout(resolve, 1400))
  for (const note of notes) {
    const target = note.targets[0]
    const where = target?.file ? `${target.file}:${target.range}` : "the page"
    server.updateNote(note.id, { status: "resolved", from: "agent", agent: "Your agent", message: `Done. I changed ${where} (this is the demo, so nothing was written).` })
  }
  document.dispatchEvent(new Event("turbo:load"))
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start)
else start()
