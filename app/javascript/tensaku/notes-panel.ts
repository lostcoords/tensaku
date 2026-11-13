// The notes panel: this page's notes, every page's, or the archive, as cards, with the copy buttons and
// who is listening for notes.

import { api, query } from "./api"
import { icon } from "./icons"
import { noteCard, openAgents } from "./note-card"
import { closed, currentNotes, listeners, load, type Note, onRender, openNotes, type Scope, scopedNotes, setScope } from "./notes"
import { settings } from "./settings"
import { activeInShadow, copy, div, fixed, h, toast } from "./ui"

let sidebar: HTMLElement | null = null
let scope: Scope = "page"

export function toggleSidebar(force?: boolean) {
  const show = force ?? !sidebar?.isConnected
  if (!show) { sidebar?.remove(); setScope(null); return }
  sidebar ??= div("sidebar")
  sidebar.setAttribute("role", "complementary")
  sidebar.setAttribute("aria-label", "Tensaku notes")
  fixed.append(sidebar)
  setScope(scope)
  renderSidebar()
}

export const sidebarOpen = () => Boolean(sidebar?.isConnected)

// A card being edited or answered is left alone when a poll redraws.
onRender(({ force }) => {
  if (!sidebar?.isConnected) return
  const typing = activeInShadow()
  if (force || !(typing?.matches("textarea, input") && sidebar.contains(typing))) renderSidebar()
})

async function showScope(next: Scope) {
  scope = next
  await setScope(next)
  renderSidebar()
}

// Resolved and declined notes have served their purpose once checked. Archiving moves the ones in the
// panel's scope out of it; agents can still list them, and reopening one brings it back.
async function clearDone(done: Note[]) {
  try {
    await api("POST", "/notes/archive", { ids: done.map((note) => note.id) })
    await load({ force: true })
    toast(`Archived ${done.length} done ${done.length === 1 ? "note" : "notes"}`)
  } catch (error) {
    toast((error as Error).message, { error: true })
  }
}

function renderSidebar() {
  if (!sidebar) return
  const format = settings().copyFormat === "short" ? "short" : undefined
  const copyAll = async (all: boolean) => {
    const markdown = await api<string>("GET", "/notes.md" + query(all ? { format } : { url: location.pathname, format }))
    await copy(markdown)
    toast(all ? "Copied all open notes" : "Copied this page's open notes")
  }
  const tab = (which: Scope, text: string) =>
    h("button", { type: "button", role: "tab", "aria-selected": String(scope === which), onclick: () => showScope(which) }, text)
  const card = (note: Note) => noteCard(note)
  const listed = scope === "page" ? currentNotes() : scopedNotes()
  const grouped = (list: Note[]) => scope === "page"
    ? list.map(card)
    : Array.from(new Set(list.map((note) => note.url))).flatMap((url) => [
        h("a", { className: `page${url === location.pathname ? " current" : ""}`, href: url }, url, h("span", {}, String(list.filter((note) => note.url === url).length))),
        ...list.filter((note) => note.url === url).map(card),
      ])
  const archive = scope === "archived"
  const done = archive ? [] : listed.filter(closed)
  const body: Node[] = grouped(archive ? listed.slice().reverse() : listed.filter((note) => !closed(note)))
  if (archive) {
    if (!listed.length) body.push(div("empty", "Nothing archived. Archive done moves resolved and declined notes here."))
  } else if (done.length) {
    body.push(div("section", h("span", {}, `Done (${done.length})`), h("button", { type: "button", onclick: () => clearDone(done) }, "Archive done")), ...grouped(done))
  } else if (!listed.length) {
    body.push(div("empty", scope === "page" ? "No notes on this page. Select an element or drag over an area to add one." : "No notes yet."))
  }
  sidebar.replaceChildren(
    h("header", {}, h("strong", {}, scope === "page" ? `Notes on ${location.pathname}` : archive ? "Archived notes" : "Notes on every page"), h("button", { type: "button", className: "icon-button", onclick: () => toggleSidebar(false), "aria-label": "Close notes" }, icon("close"))),
    div("tabs", tab("page", "This page"), tab("all", "All pages"), tab("archived", "Archive")),
    ...body,
    ...(openNotes() ? [sendBar(copyAll)] : []))
}

function sendBar(copyAll: (all: boolean) => void) {
  const names = listeners()
  const status = names.length
    ? div("listener on", h("span", { className: "dot" }), names.length === 1 ? `${names[0]} is checking for notes` : `${names.length} agents are checking for notes`)
    : div("listener", h("span", { className: "dot" }), "No agent listening",
        h("button", { type: "button", className: "link", onclick: openAgents }, "Connect one"))
  // The copy buttons act on the notes above them, so they sit above the rule; who gets the notes is below it.
  return div("copy-bar",
    div("actions",
      h("button", { type: "button", onclick: () => copyAll(false) }, "Copy page"),
      h("button", { type: "button", onclick: () => copyAll(true) }, `Copy all (${openNotes()})`)),
    status)
}
