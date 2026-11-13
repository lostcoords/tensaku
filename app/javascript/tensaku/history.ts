// Undo and redo of saves made in this tab.
//
// Every save is an entry: what changed, from what to what, as data, so the stacks survive a reload
// (sessionStorage, per tab). Undo reverts the latest save, or a chosen one, and moves it to the redo
// stack; redo applies the latest undone edit again; a new save clears the redo stack. Each step checks
// that the source still holds the text it expects, like any save.

import { api, ApiError, query } from "./api"
import { MARKDOWN, STAMP, translationOf } from "./dom"
import { replaceText, type SourceKind } from "./refresh"
import { type Description, finish, rangeAfter, report, type SaveResult, showTranslation, textNodesOf, type TextPiece } from "./save"
import { toast } from "./ui"


type Op =
  | { kind: "template"; stamp: string; changes: { index: number; from: string; to: string }[] }
  | { kind: "attribute"; stamp: string; changes: { name: string; index: number; from: string; to: string }[] }
  // Every locale saved from one translation editor, undone and redone together.
  | { kind: "translation"; key: string; changes: { locale: string; from: string; to: string }[] }
  // range covers the block as it reads now: after `to` when done, after `from` when undone.
  | { kind: "markdown"; range: string; prefix: string; from: string; to: string; tag?: string }
export interface Entry { id: number; label: string; key: string | null; file?: string; at: string; op: Op }

const HISTORY_LIMIT = 50
const HISTORY_KEY = "tensaku:history"
let done: Entry[] = []
let undone: Entry[] = []
try {
  const saved = JSON.parse(sessionStorage.getItem(HISTORY_KEY) ?? "null")
  if (saved && Array.isArray(saved.done) && Array.isArray(saved.undone)) ({ done, undone } = saved)
} catch {
  // Blocked storage: the stacks start empty and last until the page is left.
}
function persist() {
  try {
    sessionStorage.setItem(HISTORY_KEY, JSON.stringify({ done, undone }))
  } catch {
    // Blocked storage: the stacks still work on this page.
  }
}
const nextId = () => Math.max(0, ...done.map((entry) => entry.id), ...undone.map((entry) => entry.id)) + 1

export function record(element: Element | null, label: string, op: Op, file?: string): Entry {
  const entry: Entry = { id: nextId(), label, key: element ? undoKey(element) : null, file, at: new Date().toISOString(), op }
  done.push(entry)
  if (done.length > HISTORY_LIMIT) done.shift()
  undone = []
  persist()
  return entry
}

// The saves for the history popover, newest first: those that can be undone, and those that can be
// redone (only the latest of these with Redo).
export function editHistory() {
  return { done: done.slice().reverse(), undone: undone.slice().reverse() }
}

export const canUndo = () => done.length > 0
export const canRedo = () => undone.length > 0

// Reverts entry, or the latest save, and puts it on the redo stack.
export async function undo(entry: Entry | undefined = done[done.length - 1]) {
  if (!entry || !done.includes(entry)) return toast("That edit was undone already.")
  try {
    const result = await apply(entry.op, true)
    done = done.filter((item) => item !== entry)
    undone.push(entry)
    persist()
    finish(result, sourceKind(entry.op), `Undid ${entry.label}`, { Redo: () => redo(entry) })
  } catch (error) {
    report(error)
  }
}

export async function redo(entry: Entry | undefined = undone[undone.length - 1]) {
  if (!entry || undone[undone.length - 1] !== entry) return toast("Only the latest undone edit can be redone.")
  try {
    const result = await apply(entry.op, false)
    undone.pop()
    done.push(entry)
    persist()
    finish(result, sourceKind(entry.op), `Redid ${entry.label}`, { Undo: () => undo(entry) })
  } catch (error) {
    report(error)
  }
}

const sourceKind = (op: Op): SourceKind => op.kind === "attribute" ? "template" : op.kind

// The latest save on element that can still be undone.
export function undoFor(element: Element): Entry | undefined {
  const key = undoKey(element)
  return key ? done.slice().reverse().find((entry) => entry.key === key) : undefined
}

// Writes op's `from` back over `to` (undo), or `to` over `from` (redo), after checking the source
// still reads what the step expects.
async function apply(op: Op, reverse: boolean): Promise<SaveResult> {
  const verb = reverse ? "undone" : "redone"
  const stale = (what: string) => new ApiError(`The ${what} changed since the edit, so it can't be ${verb} here.`, 409, true)
  if (op.kind === "template") {
    const fresh = await api<Description>("GET", "/source" + query({ stamp: op.stamp }))
    const texts = fresh.pieces.filter((p): p is TextPiece => p.kind === "text")
    const edits = op.changes.map(({ index, from, to }) => {
      const [current, target] = reverse ? [to, from] : [from, to]
      const now = texts[index]
      if (!now || now.text !== current) throw stale("text")
      return { piece: now, current, target }
    })
    const result = await api<SaveResult>("POST", "/text", { stamp: op.stamp, edits: edits.map(({ piece, target }) => ({ start: piece.start, end: piece.end, original: piece.raw, text: target })) })
    const nodes = textNodesOf(op.stamp)
    edits.forEach(({ current, target }) => replaceText(nodes, current, target))
    return result
  }
  if (op.kind === "attribute") {
    let result: SaveResult = {}
    for (const { name, index, from, to } of op.changes) {
      const [current, target] = reverse ? [to, from] : [from, to]
      const fresh = await api<Description>("GET", "/source" + query({ stamp: op.stamp }))
      const now = fresh.attributes.find((a) => a.name === name)?.pieces.filter((p): p is TextPiece => p.kind === "text")[index]
      if (!now || now.text !== current) throw stale("attribute")
      result = await api<SaveResult>("POST", "/attribute", { stamp: op.stamp, name, start: now.start, end: now.end, original: now.raw, text: target })
      document.querySelectorAll(`[${STAMP}="${CSS.escape(op.stamp)}"]`).forEach((el) => {
        const value = el.getAttribute(name)
        if (value !== null) el.setAttribute(name, value.replace(current, target))
      })
    }
    return { ...result, changed: true }
  }
  if (op.kind === "translation") {
    let result: SaveResult = {}
    for (const { locale, from, to } of op.changes) {
      const [current, target] = reverse ? [to, from] : [from, to]
      const saved = await api<SaveResult>("POST", "/translation", { locale, key: op.key, original: current, text: target })
      result = { ...saved, file: result.file ?? saved.file, changed: true }
      showTranslation({ locale, key: op.key }, current, target)
    }
    return result
  }
  const [current, target] = reverse ? [op.to, op.from] : [op.from, op.to]
  const result = await api<SaveResult>("POST", "/markdown", { range: op.range, original: op.prefix + current, text: target, tag: op.tag })
  op.range = rangeAfter(op.range, op.prefix + target)
  return result
}

// The element's source position, so the element menu can undo its latest save, or null when it has
// none (a translated attribute on an element without a stamp).
function undoKey(element: Element): string | null {
  const translation = translationOf(element)
  return element.getAttribute(STAMP) ?? element.getAttribute(MARKDOWN) ?? (translation ? `${translation.locale}.${translation.key}` : null)
}
