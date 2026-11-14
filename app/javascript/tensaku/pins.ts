// The pins: one numbered marker per note on this page, where it was written or next to what it points
// at, and a highlight on the phrase a text note is about. A click opens the note's card.

import { icon } from "./icons"
import { showNote } from "./note-card"
import { anchorFor, phraseRects, pointFor } from "./note-targets"
import { currentNotes, type Note, onRender } from "./notes"
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

export function drawPins() {
  pinLayer.replaceChildren()
  currentNotes().forEach((note, index) => {
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
    const pin = h("button", { className: `pin ${note.status}${fresh ? " fresh" : ""}`, title: note.comment, "aria-label": `Note ${index + 1}: ${note.comment}`, "data-note": note.id },
      note.status === "resolved" ? icon("check") : note.status === "declined" ? icon("close") : String(index + 1))
    Object.assign(pin.style, { left: `${point ? point.x : rect.right}px`, top: `${rect.top}px` })
    pin.addEventListener("click", (event) => { event.stopPropagation(); showNote(note, rect) })
    pinLayer.append(pin)
  })
}
