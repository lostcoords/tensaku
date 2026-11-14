// Notes: comments on elements or areas that an agent reads with the file and line attached, stored by
// the server in Tensaku's database. This module holds the page's copy of the notes and the connected
// agents, keeps it current, and tells the views (pins.ts, note-card.ts, notes-panel.ts, announce.ts)
// when it changes.

import { api, ApiError, meta, query } from "./api"
import type { contextOf } from "./dom"
import { settings } from "./settings"
import { toast } from "./ui"
import { refreshAfterAgent } from "./refresh"

export interface Target {
  kind: "element" | "text" | "translation" | "markdown"
  stamp?: string
  text?: string
  tag?: string
  key?: string
  locale?: string
  md?: string
  context?: ReturnType<typeof contextOf>
  classes?: string[]
  // Where the note was written on the element, as fractions of its box from the top left.
  point?: [number, number]
  file?: string
  range?: string
}

export interface Note {
  id: string
  url: string
  comment: string
  targets: Target[]
  rect?: { x: number; y: number; width: number; height: number }
  viewport?: string
  status: "open" | "working" | "question" | "resolved" | "declined"
  sent_at?: string
  // Set when watch_notes handed the note to an agent.
  delivered_at?: string
  delivered_to?: string
  // In progress, but its session's process ended.
  stopped?: boolean
  // Set when the page took a screenshot of what the note points at (GET /notes/ID/screenshot).
  screenshot?: { width: number; height: number }
  thread?: { from: "you" | "agent"; text: string; agent?: string; at: string }[]
  agent?: string
  created_at: string
}

// An agent whose `tensaku mcp` is running: where and since when, whether it waits in watch_notes, its
// last tool call and the notes it works on.
export interface Agent {
  name: string
  // Two words from the session id, such as amber-fox. The agent tells the person, so a terminal can
  // be matched to its row.
  handle?: string
  folder?: string
  started_at?: string
  listening: boolean
  last?: { tool: string; note?: string; at: string }
  working: { id: string; url: string; comment: string }[]
  // Started before Tensaku's code last changed.
  outdated?: boolean
  // Notes are pushed into its chat over a Claude Code channel.
  channel?: boolean
}

// Which notes the notes panel lists besides this page's: every page's, or the archive. null while the
// panel is closed or shows this page.
export type Scope = "page" | "all" | "archived"

let notes: Note[] = []
let scoped: Note[] = []
let scope: Scope | null = null
let openCount = 0
let agents: Agent[] = []

export const currentNotes = () => notes
export const scopedNotes = () => scoped
export const currentAgents = () => agents
export const openNotes = () => openCount
export const agentLabel = (agent: Agent) => agent.handle ? `${agent.name} · ${agent.handle}` : agent.name
// The agents waiting in watch_notes.
export const listeners = () => agents.filter((agent) => agent.listening).map(agentLabel)
export const closed = (note: Note) => note.status === "resolved" || note.status === "declined"

// What happened, for the views: a load (forced, or from a poll that found something new; first for the
// page's first), or one note changed from this page, which an open card shows even while you type in it.
export interface Render { force: boolean; first?: boolean; changed?: Note }
const renderListeners: ((render: Render) => void)[] = []
const countListeners: ((count: number) => void)[] = []
const agentListeners: ((agents: Agent[]) => void)[] = []
const changeListeners: ((before: Note[], after: Note[]) => void)[] = []

export const onRender = (listener: (render: Render) => void) => renderListeners.push(listener)
export const onCount = (listener: (count: number) => void) => countListeners.push(listener)
export const onAgents = (listener: (agents: Agent[]) => void) => agentListeners.push(listener)
// Every load after the first that found the notes changed, with the notes before and after.
export const onChanges = (listener: (before: Note[], after: Note[]) => void) => changeListeners.push(listener)

// The server leaves out empty fields, so a note made without targets has none.
const normalized = (list: Note[]) => list.map((note) => ({ ...note, targets: note.targets ?? [] }))

let lastSignature = ""
// Polls and forced loads can overlap; only the newest request's answer is used.
let loadSequence = 0
// A 403 means the page's token no longer matches the server's (tmp/tensaku/token changed). Said once, not on every
// poll; the notes already drawn stay.
let tokenWarned = false
// Said once per page load.
let restartWarned = false
let agentChangedAt: string | undefined
let primed = false

export async function load({ force = false } = {}) {
  const sequence = ++loadSequence
  let first = false
  try {
    const data = await api<{ notes: Note[]; open: number; agents?: Agent[]; restart?: boolean; changed_at?: string }>("GET", "/notes" + query({ url: location.pathname }))
    if (sequence !== loadSequence) return
    tokenWarned = false
    // An agent resolved a note since the last load, on any page: the page shows the change.
    if (primed && data.changed_at && data.changed_at !== agentChangedAt) refreshAfterAgent()
    agentChangedAt = data.changed_at
    if (data.restart && !restartWarned) {
      restartWarned = true
      toast("Tensaku's code changed since this dev server started, so the page runs a newer overlay than the server. Restart the dev server.", { error: true, timeout: 20000 })
    }
    // A note deleted from the page waits a few seconds on the server, for its Undo.
    data.notes = data.notes.filter((note) => !pendingDeletes.has(note.id))
    agents = data.agents ?? []
    agentListeners.forEach((listener) => listener(agents))
    const signature = location.pathname + JSON.stringify([data.notes, data.open, listeners()])
    if (!force && signature === lastSignature) return
    // Nothing is kept until the scope's notes are in too: a newer load cancels this one, and it must not
    // find the signature already taken and skip the scope's notes.
    const which = scope
    const all = which && which !== "page" ? await scopeNotes(which) : null
    if (sequence !== loadSequence) return
    lastSignature = signature
    const after = normalized(data.notes)
    if (primed && data.notes.length && notes.length) changeListeners.forEach((listener) => listener(notes, after))
    first = !primed
    primed = true
    notes = after
    openCount = data.open
    if (all && scope === which) scoped = all
  } catch (error) {
    if (sequence !== loadSequence) return
    if (error instanceof ApiError && error.status === 403 && !tokenWarned) {
      tokenWarned = true
      toast(`${error.message} Notes can't be loaded until then.`, { error: true, timeout: 15000, actions: { Reload: () => location.reload() } })
    }
    return
  }
  countListeners.forEach((listener) => listener(openCount))
  render({ force, first })
}

function render(what: Render) {
  renderListeners.forEach((listener) => listener(what))
}

// Every page's notes, or the archive: resolved and declined notes moved out of the panel.
const scopeNotes = async (which: Exclude<Scope, "page">) =>
  normalized((await api<{ notes: Note[] }>("GET", "/notes" + (which === "archived" ? query({ archived: "1" }) : ""))).notes).filter((note) => !pendingDeletes.has(note.id))

// The notes panel shows scope (null once it closes); every load from then on fetches its notes too.
export async function setScope(which: Scope | null) {
  scope = which
  if (which && which !== "page") scoped = await scopeNotes(which)
}

// Notes change from outside the page too (an agent starts or resolves one). The dev server streams an
// event whenever the notes or the agents change, and the page loads them then. While an agent works on
// a note, it also streams an event whenever the app's files change, and the page fetches itself again to
// show the edit. While the stream is
// down, the page asks every four seconds while the tab is visible (every 16 in a hidden tab with
// notifications on), and reconnects every five. A server that can't stream (501) is only polled.
// Nothing is redrawn when the answer is the same.
let streaming = false
export function poll() {
  let pending = 0
  const changed = () => { clearTimeout(pending); pending = window.setTimeout(() => load(), 30) }
  // An agent often saves several files in a row, and a CSS watcher rebuilds right after: one fetch.
  let editedPending = 0
  const edited = () => { clearTimeout(editedPending); editedPending = window.setTimeout(refreshAfterAgent, 150) }
  const connect = async () => {
    let retry = 5000
    try {
      const { token, root } = meta()
      const response = await fetch(root + "/events", { headers: { "X-Tensaku-Token": token, Accept: "text/event-stream" }, credentials: "same-origin" })
      if (response.status === 501) return
      if (!response.ok || !response.body) throw new Error(`events ${response.status}`)
      streaming = true
      const reader = response.body.pipeThrough(new TextDecoderStream()).getReader()
      let buffer = ""
      for (;;) {
        const { value, done } = await reader.read()
        if (done) break
        buffer += value
        const events = buffer.split("\n\n")
        buffer = events.pop() ?? ""
        if (events.includes("data: changed")) changed()
        if (events.includes("data: edited")) edited()
      }
    } catch {
      retry = 15000
    }
    streaming = false
    setTimeout(connect, retry)
  }
  const tick = async () => {
    if (!streaming && (document.visibilityState === "visible" || settings().notify)) await load()
    setTimeout(tick, document.visibilityState === "visible" ? 4000 : 16000)
  }
  connect()
  setTimeout(tick, 4000)
}

// Changes made from this page, so they aren't announced as the agent's (see announce.ts).
const localChanges = new Set<string>()
export const changedHere = (id: string) => localChanges.delete(id)

// Puts a note's new state everywhere it shows, or takes it away (removed).
function replace(note: Note, removed = false) {
  const swap = (list: Note[]) => removed ? list.filter((other) => other.id !== note.id) : list.map((other) => other.id === note.id ? note : other)
  notes = swap(notes)
  scoped = swap(scoped)
  lastSignature = ""
  render({ force: true, changed: removed ? undefined : note })
}

// What a change made from the page will look like once saved, to show it before the server answers.
export type NoteChange = { status?: Note["status"]; comment?: string; message?: string; to?: string }
function predicted(note: Note, change: NoteChange): Note {
  const next: Note = { ...note, thread: [...(note.thread ?? [])] }
  if (change.comment) next.comment = change.comment
  if (change.message) next.thread!.push({ from: "you", text: change.message, at: new Date().toISOString() })
  if (change.status) next.status = change.status
  if (change.to !== undefined) {
    const chosen = agents.find((agent) => agent.handle === change.to)
    Object.assign(next, { status: "open", agent: chosen ? agentLabel(chosen) : undefined, delivered_at: undefined, delivered_to: undefined, stopped: undefined })
  }
  // Only an edit, a message or an assignment sends the note to an agent again.
  if (next.status === "open" && (change.comment || change.message || change.to !== undefined)) next.sent_at = new Date().toISOString()
  return next
}

// Optimistic: the change shows at once (onChange gets the note's new state), and goes back with a toast
// if the server refuses it. Resolves once the server answered, with whether it saved.
export async function updateNote(note: Note, change: NoteChange, onChange: (note: Note) => void = () => {}) {
  const after = predicted(note, change)
  localChanges.add(note.id)
  replace(after)
  onChange(after)
  try {
    await api("PATCH", `/notes/${note.id}`, change)
    load({ force: true })
    return true
  } catch (error) {
    localChanges.delete(note.id)
    replace(note)
    onChange(note)
    toast((error as Error).message, { error: true })
    return false
  }
}

// A deleted note leaves the page at once and is deleted on the server a few seconds later, so its
// toast can undo it. Leaving the page deletes it right away.
const pendingDeletes = new Map<string, () => void>()
addEventListener("pagehide", () => pendingDeletes.forEach((commit) => commit()))
export function deleteLater(note: Note) {
  replace(note, true)
  let done = false
  const commit = () => {
    if (done) return
    done = true
    pendingDeletes.delete(note.id)
    api("DELETE", `/notes/${note.id}`).catch((error) => toast((error as Error).message, { error: true })).finally(() => load({ force: true }))
  }
  pendingDeletes.set(note.id, commit)
  const timer = setTimeout(commit, 6000)
  toast("Note deleted", { timeout: 6000, actions: { Undo: () => { done = true; clearTimeout(timer); pendingDeletes.delete(note.id); load({ force: true }) } } })
}

export async function deleteNotes(list: Note[]) {
  try {
    for (const note of list) await api("DELETE", `/notes/${note.id}`)
  } finally {
    await load({ force: true })
  }
}
