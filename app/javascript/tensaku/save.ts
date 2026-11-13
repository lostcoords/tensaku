// What the source endpoints answer, and what the page does after a save, from the editor or from undo
// and redo (history.ts).

import { type Diff, diffRows } from "./diff"
import { ApiError } from "./api"
import { elementsWithAttributeKey, nodesForKey, type TranslationKey } from "./markers"
import { STAMP, utf8Length } from "./dom"
import { refresh, replaceText, type SourceKind } from "./refresh"
import { toast } from "./ui"

export interface TextPiece { kind: "text"; start: number; end: number; raw: string; text: string; index?: number }
export interface ElementPiece { kind: "element"; tag: string; label: string; stamp?: string | null }
export type Piece = TextPiece | { kind: "ruby"; code: string } | ElementPiece | { kind: "hidden" }
export interface Attribute { name: string; quote: string | null; pieces: Piece[] }
export interface Description { file: string; stamp: string; range: string; tag: string; helper: boolean; editable: boolean; pieces: Piece[]; attributes: Attribute[] }
export interface LocaleEntry { file?: string; line?: number; value: string | null; editable: boolean }
export interface MarkdownDescription { file: string; range: string; editable: boolean; prefix: string; text: string; original: string }

export type SaveResult = { changed?: boolean; file?: string; warning?: string; diff?: Diff }

export const INTERPOLATION = /(%\{[^}]+\})/

// Says where a save landed, with a diff when the server sent one, and refreshes the page's content.
export function finish(result: SaveResult, kind: SourceKind, verb: string, actions?: Record<string, () => void>) {
  if (!result.changed) return
  const where = result.diff ? `${result.file}:${result.diff.line}` : result.file ?? ""
  toast(`${verb} ${where}`.trim(), {
    timeout: result.diff ? 8000 : undefined,
    detail: result.diff ? diffRows(result.diff) : undefined,
    actions,
  })
  if (result.warning) toast(result.warning, { timeout: 8000 })
  refresh(kind)
}

// An error from the editor or from undo and redo; a stale source offers a reload.
export function report(error: unknown) {
  const message = error instanceof Error ? error.message : String(error)
  toast(message, { error: true, actions: error instanceof ApiError && error.stale ? { Reload: () => location.reload() } : undefined })
}


// A Markdown block's range once its source is text: same start, the end moved to where text ends.
export function rangeAfter(range: string, text: string) {
  const [, path, startLine, startColumn] = range.match(/^(.+):(\d+):(\d+)-/)!
  const lines = text.split("\n")
  const endLine = Number(startLine) + lines.length - 1
  const endColumn = (lines.length === 1 ? Number(startColumn) - 1 : 0) + utf8Length(lines[lines.length - 1])
  return `${path}:${startLine}:${startColumn}-${endLine}:${endColumn}`
}

// The text nodes directly inside the elements a template element rendered.
export const textNodesOf = (stamp: string) => Array.from(document.querySelectorAll(`[${STAMP}="${CSS.escape(stamp)}"]`)).flatMap((el) =>
  Array.from(el.childNodes).filter((node): node is Text => node.nodeType === Node.TEXT_NODE))

// Shows a saved translation on the page, unless it has interpolations the page filled in.
export function showTranslation(key: TranslationKey, from: string, to: string) {
  if (INTERPOLATION.test(from)) return
  replaceText(nodesForKey(key), from, to)
  elementsWithAttributeKey(key).forEach(({ element: el, name }) => { if (el.getAttribute(name) === from) el.setAttribute(name, to) })
}
