// Toasts, and system notifications in a hidden tab when turned on, for what agents did to the notes:
// resolved, declined, asked or replied. The pulsing pin already shows that an agent started on a note.

import { showNote } from "./note-card"
import { anchorFor } from "./note-targets"
import { toggleSidebar } from "./notes-panel"
import { changedHere, type Note, onChanges } from "./notes"
import { settings } from "./settings"
import { toast } from "./ui"

type Change = "resolved" | "declined" | "question" | "message"

// An agent can change many notes between two polls. Toasts appear one at a time, at most three at
// once, and a longer backlog becomes one toast that counts the changes.
const SHOWN_AT_ONCE = 3
const PACE = 1200
const waiting: { note: Note; what: Change }[] = []
let shownToasts: HTMLElement[] = []
let paceTimer = 0

const whoChanged = (note: Note) => note.agent ?? note.thread?.filter((entry) => entry.from === "agent").pop()?.agent ?? "The agent"

function notify(text: string, tag: string) {
  if (document.visibilityState !== "visible" && settings().notify && "Notification" in window && Notification.permission === "granted") {
    new Notification("Tensaku", { body: text, tag })
  }
}

function announceOne(note: Note, what: Change) {
  const who = whoChanged(note)
  const about = `"${note.comment.length > 48 ? note.comment.slice(0, 48) + "…" : note.comment}"`
  const text = { resolved: `${who} resolved ${about}`, declined: `${who} declined ${about}`, question: `${who} has a question on ${about}`, message: `${who} replied on ${about}` }[what]
  notify(text, `tensaku-${note.id}`)
  return toast(text, { actions: { Show: () => { const rect = anchorFor(note); if (rect) { scrollTo({ top: Math.max(0, rect.top - 120), behavior: "smooth" }); showNote(note, rect) } } } })
}

function announceSummary(changes: { note: Note; what: Change }[]) {
  const names = new Set(changes.map((change) => whoChanged(change.note)))
  const who = names.size === 1 ? Array.from(names)[0] : "Agents"
  const count = (what: Change) => changes.filter((change) => change.what === what).length
  const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`
  const parts = [
    count("resolved") && `resolved ${plural(count("resolved"), "note")}`,
    count("declined") && `declined ${plural(count("declined"), "note")}`,
    count("question") && `asked ${plural(count("question"), "question")}`,
    count("message") && `replied on ${plural(count("message"), "note")}`,
  ].filter(Boolean) as string[]
  const text = `${who} ${parts.slice(0, -1).join(", ")}${parts.length > 1 ? " and " : ""}${parts[parts.length - 1]}`
  notify(text, "tensaku-summary")
  return toast(text, { timeout: 8000, actions: { Show: () => toggleSidebar(true) } })
}

function nextAnnouncement() {
  paceTimer = 0
  if (!waiting.length) return
  shownToasts = shownToasts.filter((element) => element.isConnected)
  if (shownToasts.length < SHOWN_AT_ONCE) {
    if (waiting.length > SHOWN_AT_ONCE) shownToasts.push(announceSummary(waiting.splice(0)))
    else { const change = waiting.shift()!; shownToasts.push(announceOne(change.note, change.what)) }
  }
  if (waiting.length) paceTimer = window.setTimeout(nextAnnouncement, PACE)
}

function announce(note: Note, what: Change) {
  // The latest change to a note replaces one still waiting.
  const queued = waiting.findIndex((change) => change.note.id === note.id)
  if (queued >= 0) waiting.splice(queued, 1)
  waiting.push({ note, what })
  // Not shown right away: every change from this poll has to be waiting first to count as a backlog.
  if (!paceTimer) paceTimer = window.setTimeout(nextAnnouncement)
}

onChanges((before, after) => {
  const old = new Map(before.map((note) => [note.id, note]))
  for (const note of after) {
    const previous = old.get(note.id)
    if (!previous) continue
    if (changedHere(note.id)) continue
    const messages = note.thread?.length ?? 0
    if (messages > (previous.thread?.length ?? 0) && note.thread![messages - 1].from === "agent" && note.status === previous.status) announce(note, "message")
    else if (note.status !== previous.status && note.status !== "open" && note.status !== "working") announce(note, note.status)
  }
})
