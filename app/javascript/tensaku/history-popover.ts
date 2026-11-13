// The Edit history popover: the saves made in this tab, with undo and redo.

import { isApple } from "./api"
import { editHistory, redo, undo } from "./editor"
import { ago, closePopover } from "./popover"
import { div, h } from "./ui"

// Cmd/Ctrl+Z undoes the latest save, Cmd/Ctrl+Shift+Z or Ctrl+Y redoes (index.ts handles the keys).
export const UNDO_KEYS = isApple ? "⌘Z and ⇧⌘Z" : "Ctrl+Z and Ctrl+Y"

// The saves in this tab, newest first, with Undo on each, and the undone ones below, the latest with
// Redo. Undo and redo also work from the keyboard (UNDO_KEYS).
export function renderHistory(): Node[] {
  const { done, undone } = editHistory()
  const row = (entry: (typeof done)[number], action: Node) => div(`entry${undone.includes(entry) ? " undone" : ""}`,
    div("what", h("span", {}, entry.label), h("span", { className: "where" }, `${entry.file ?? ""} · ${ago(new Date(entry.at))}`)), action)
  const button = (text: string, run: () => Promise<unknown>) => h("button", { type: "button", onclick: async () => { await run(); closePopover() } }, text)
  return [
    h("h3", {}, "Edit history", h("span", { className: "where" }, `Saves in this tab. ${UNDO_KEYS} undo and redo.`)),
    ...(done.length || undone.length ? [
      ...done.map((entry) => row(entry, button("Undo", () => undo(entry)))),
      ...undone.map((entry, i) => row(entry, i === 0 ? button("Redo", () => redo(entry)) : h("span", { className: "where" }, "undone"))),
    ] : [div("empty", "No edits yet.")]),
  ]
}
