// A stand-in for Tensaku's Rails endpoints, for the landing page's demo. It answers the overlay's
// requests from the recording in data.js and splices an in-memory copy of the landing page's ERB file the
// same way Tensaku splices the real one: by byte range, after checking the bytes are still the ones
// the editor loaded.

import data from "demo/data"

const clone = (value) => JSON.parse(JSON.stringify(value))

export class DemoServer {
  constructor() {
    this.source = data.source
    this.stamps = clone(data.stamps)
    this.notes = []
    this.listeners = new Set()
    this.lastChange = null
  }

  onChange(listener) {
    this.listeners.add(listener)
  }

  changed(kind) {
    this.listeners.forEach((listener) => listener(kind))
  }

  // The overlay's requests, by method and path. Returns [status, body].
  handle(method, url, body) {
    const path = url.pathname
    const params = url.searchParams
    if (method === "GET" && path === "/source") return this.describe(params.get("stamp"))
    if (method === "POST" && path === "/text") return this.editText(body)
    if (method === "POST" && path === "/attribute") return this.editAttribute(body)
    if (method === "POST" && path === "/selection") return [200, { ok: true }]
    if (method === "GET" && path === "/notes") return [200, this.listNotes(params.get("url"))]
    if (method === "GET" && path === "/notes.md") return [200, this.markdown(this.notesFor(params))]
    if (method === "POST" && path === "/notes") return this.createNote(body)
    const id = path.match(/^\/notes\/([a-z0-9]+)$/)?.[1]
    if (id && method === "PATCH") return this.updateNote(id, body)
    if (id && method === "DELETE") return this.deleteNote(id)
    if (path === "/translation" || path === "/markdown") return [404, { error: "This demo only edits an ERB template." }]
    return [404, { error: "Not found" }]
  }

  describe(stamp) {
    const description = this.stamps[stamp]
    if (!description) return [404, { error: `No element at ${stamp}` }]
    const { element, ...rest } = description
    return [200, clone(rest)]
  }

  textPieces(stamp) {
    return this.stamps[stamp].pieces.filter((piece) => piece.kind === "text")
  }

  editText({ stamp, edits }) {
    if (!this.stamps[stamp]) return [404, { error: `No element at ${stamp}` }]
    const pieces = this.textPieces(stamp)
    const planned = edits.map((edit) => {
      const piece = pieces.find((p) => p.start === edit.start && p.end === edit.end)
      if (!piece) return null
      return { piece, raw: rewrite(piece, edit.text, escapeText), original: edit.original }
    })
    if (planned.includes(null)) return stale()
    return this.splice(planned)
  }

  editAttribute({ stamp, name, start, end, original, text }) {
    const attribute = this.stamps[stamp]?.attributes.find((a) => a.name === name)
    const piece = attribute?.pieces.find((p) => p.kind === "text" && p.start === start && p.end === end)
    if (!piece) return stale()
    return this.splice([{ piece, raw: escapeAttribute(text, attribute.quote), original, text }])
  }

  // Replaces each piece's bytes, last first, and moves every later offset by the difference.
  splice(planned) {
    for (const { piece, original } of planned) {
      if (this.source.slice(piece.start, piece.end) !== original) return stale()
    }
    const everyPiece = Object.values(this.stamps).flatMap((d) => [...d.pieces, ...d.attributes.flatMap((a) => a.pieces)]).filter((p) => p.kind === "text")
    const sorted = [...planned].sort((a, b) => b.piece.start - a.piece.start)
    let first = Infinity
    let last = 0
    for (const { piece, raw } of sorted) {
      const { start, end } = piece
      const delta = raw.length - (end - start)
      this.source = this.source.slice(0, start) + raw + this.source.slice(end)
      for (const other of everyPiece) {
        if (other.start === start && other.end === end) continue
        if (other.start >= end) { other.start += delta; other.end += delta }
      }
      // Every copy of a piece (a loop renders one stamp many times) shares the same object.
      piece.end = start + raw.length
      piece.raw = raw
      piece.text = unescape(raw).replace(/\s+/g, " ")
      if (piece.trim_start) piece.text = piece.text.trimStart()
      if (piece.trim_end) piece.text = piece.text.trimEnd()
      // The change, without the whitespace kept around it.
      first = Math.min(first, start + raw.match(/^\s*/)[0].length)
      last = Math.max(last, start + raw.trimEnd().length)
    }
    this.lastChange = { start: first, end: last }
    this.changed("source")
    return [200, { changed: true, file: data.file }]
  }

  // Notes -------------------------------------------------------------------------------------

  listNotes(url) {
    const notes = this.notes.filter((note) => !url || note.url === url)
    return { notes: clone(notes), open: this.notes.filter((n) => n.status === "open" || n.status === "question").length }
  }

  notesFor(params) {
    if (params.get("id")) return this.notes.filter((n) => n.id === params.get("id"))
    return this.notes.filter((n) => n.status !== "resolved" && (!params.get("url") || n.url === params.get("url")))
  }

  createNote({ url, comment, targets, viewport, rect }) {
    const now = new Date().toISOString()
    const note = {
      id: Math.random().toString(36).slice(2, 6),
      url,
      comment,
      targets: (targets ?? []).map((target) => this.target(target)),
      viewport,
      rect,
      status: "open",
      created_at: now,
      updated_at: now,
      reply: null,
    }
    this.notes.push(note)
    this.changed("notes")
    return [201, clone(note)]
  }

  // What Tensaku's Notes.target adds: the file and the element's full range, from its stamp.
  target(raw) {
    const target = { kind: raw.kind, text: raw.text, tag: raw.tag, context: raw.context }
    const description = raw.stamp && this.stamps[raw.stamp]
    if (description) Object.assign(target, { stamp: raw.stamp, file: description.file, range: description.element.range, tag: description.element.tag })
    return target
  }

  updateNote(id, { status, reply, comment }) {
    const note = this.notes.find((n) => n.id === id)
    if (!note) return [404, { error: "No such note" }]
    if (comment) note.comment = comment
    if (reply !== undefined) note.reply = reply
    if (status) note.status = status
    note.updated_at = new Date().toISOString()
    this.changed("notes")
    return [200, clone(note)]
  }

  deleteNote(id) {
    this.notes = this.notes.filter((n) => n.id !== id)
    this.changed("notes")
    return [200, { deleted: true }]
  }

  // Tensaku::Notes.to_markdown, which the MCP tools and the clipboard return.
  markdown(notes) {
    if (!notes.length) return "No notes."
    return notes.map((note) => {
      const lines = [`## Tensaku note ${note.id} (${note.status}) on ${note.url}`, "", note.comment]
      if (note.targets.length) lines.push("", ...note.targets.map((t) => `- ${targetMarkdown(t)}`))
      if (note.reply) lines.push("", `Reply: ${note.reply}`)
      return lines.join("\n")
    }).join("\n\n")
  }
}

function targetMarkdown(target) {
  const location = [target.file, target.range].filter(Boolean).join(":")
  const parts = [target.kind]
  if (target.tag) parts.push(`\`${target.tag}\``)
  if (location) parts.push(`at \`${location}\``)
  const text = (target.text ?? "").replace(/\s+/g, " ").trim()
  if (text) parts.push(`"${text.length > 120 ? text.slice(0, 117) + "..." : text}"`)
  const context = Object.entries(target.context ?? {}).filter(([, value]) => value && (!Array.isArray(value) || value.length))
  if (context.length) parts.push(`(${context.map(([key, value]) => `${key}: ${[].concat(value).join(" < ")}`).join(", ")})`)
  return parts.join(" ")
}

function stale() {
  return [409, { error: "The file changed since the page rendered. Reload to edit it.", stale: true }]
}

// Keeps the whitespace Tensaku trims at an element's edges, as Source::HtmlText#rewrite does.
function rewrite(piece, text, escape) {
  const lead = piece.trim_start ? piece.raw.match(/^\s*/)[0] : ""
  const trail = piece.trim_end ? piece.raw.match(/\s*$/)[0] : ""
  return lead + escape(text) + trail
}

const escapeText = (text) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
const escapeAttribute = (text, quote) => {
  const escaped = text.replace(/&/g, "&amp;")
  return quote === "'" ? escaped.replace(/'/g, "&#39;") : escaped.replace(/"/g, "&quot;")
}
const unescape = (raw) => raw.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&")
