// The pins: one numbered marker per note on this page, where it was written or next to what it points
// at, and a highlight on the phrase a text note is about. A click opens the note's card. A pin whose
// element was only guessed (note-targets.ts) is drawn unsure.

import { api } from "./api"
import { icon } from "./icons"
import { showNote } from "./note-card"
import { anchorFor, guessedElement, phraseRects, pointFor } from "./note-targets"
import { closed, currentNotes, load, type Note, onRender } from "./notes"
import { onRefresh } from "./refresh"
import { div, h, layer } from "./ui"

const pinLayer = div("pins")
layer.append(pinLayer)

export function setPinsHidden(hidden: boolean) {
  pinLayer.hidden = hidden
}

// Pins drop in when a note is added or changes status after the first load.
const drawn = new Map<string, Note["status"]>()
onRender(({ first }) => {
  if (first) currentNotes().forEach((note) => drawn.set(note.id, note.status))
  drawPins()
})

// An open note whose element is only a guess is held from agents until you pick it again; the server
// holds it only if the source there changed. One found for sure again is let go. Each note is asked
// about once per state, and again after a save or an agent's edit changes the source.
const asked = new Map<string, boolean>()
onRefresh(() => asked.clear())
function syncHold(note: Note, guessed: boolean) {
  if (note.status !== "open" || note.url !== location.pathname) return
  if (Boolean(note.held_at) === guessed || asked.get(note.id) === guessed) return
  asked.set(note.id, guessed)
  api("PATCH", `/notes/${note.id}`, { held: guessed }).then(() => load({ force: true })).catch(() => {})
}

export function drawPins() {
  pinLayer.replaceChildren()
  currentNotes().forEach((note, index) => {
    // A done note's text was usually changed by the agent: its pin stays green.
    const guessed = !closed(note) && Boolean(guessedElement(note))
    syncHold(note, guessed)
    const phrase = phraseRects(note)
    for (const r of phrase) {
      const mark = div(`phrase ${note.status}`)
      Object.assign(mark.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` })
      pinLayer.append(mark)
    }
    // A pin sits where the note was written, or at the top right of what it points at.
    const point = phrase.length ? null : pointFor(note)
    const rect = phrase.length ? phrase[phrase.length - 1] : point ?? anchorFor(note)
    if (!rect) return
    const fresh = drawn.get(note.id) !== note.status
    drawn.set(note.id, note.status)
    const pin = h("button", { className: `pin ${note.status}${fresh ? " fresh" : ""}${guessed || (note.held_at && !closed(note)) ? " unsure" : ""}`, title: note.comment, "aria-label": `Note ${index + 1}: ${note.comment}`, "data-note": note.id },
      note.status === "resolved" ? icon("check") : note.status === "declined" ? icon("close") : String(index + 1))
    Object.assign(pin.style, { left: `${point ? point.x : rect.right}px`, top: `${rect.top}px` })
    pin.addEventListener("click", (event) => { event.stopPropagation(); showNote(note, rect) })
    pinLayer.append(pin)
  })
}
