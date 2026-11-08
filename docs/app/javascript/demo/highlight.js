// Syntax colors for the source window. It renders on every edit, in the browser, so this is a small
// ERB tokenizer rather than Rouge.

const RUBY = /("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(:[a-z_]\w*|\b[a-z_]\w*:(?!:))/g
const TEXT = /<%[\s\S]*?%>|<!--[\s\S]*?-->|<\/?[a-zA-Z][\w-]*|[^<]+|</y
const IN_TAG = /<%[\s\S]*?%>|\/?>|["']|[^\s=<>"'/]+|[\s=/]+/y

function tokens(source) {
  const out = []
  const push = (kind, text) => { if (text) out.push({ kind, text }) }

  const erb = (tag) => {
    if (tag.startsWith("<%#")) return push("comment", tag)
    const open = tag.startsWith("<%=") ? "<%=" : "<%"
    const code = tag.slice(open.length, -2)
    push("erb", open)
    let last = 0
    for (const match of code.matchAll(RUBY)) {
      push("", code.slice(last, match.index))
      push(match[1] ? "string" : "symbol", match[0])
      last = match.index + match[0].length
    }
    push("", code.slice(last))
    push("erb", "%>")
  }

  let at = 0
  // Scans with a sticky pattern from where the last token ended.
  const next = (pattern) => {
    pattern.lastIndex = at
    const text = pattern.exec(source)?.[0]
    if (text) at += text.length
    return text
  }

  // Inside a quoted attribute value, which can hold ERB.
  const string = (quote) => {
    push("string", quote)
    while (at < source.length) {
      if (source.startsWith("<%", at)) {
        erb(next(/<%[\s\S]*?%>/y))
        continue
      }
      const stop = [ source.indexOf(quote, at), source.indexOf("<%", at) ].filter((i) => i >= 0)
      const end = stop.length ? Math.min(...stop) : source.length
      push("string", source.slice(at, end))
      at = end
      if (source[at] === quote) { push("string", quote); at += 1; return }
    }
  }

  const tag = () => {
    while (at < source.length) {
      const text = next(IN_TAG)
      if (!text) return
      if (text.startsWith("<%")) erb(text)
      else if (text === '"' || text === "'") string(text)
      else if (text.endsWith(">")) { push("tag", text); return }
      else push(/^[\s=/]+$/.test(text) ? "" : "attr", text)
    }
  }

  while (at < source.length) {
    const text = next(TEXT)
    if (text.startsWith("<%")) erb(text)
    else if (text.startsWith("<!--")) push("comment", text)
    else if (/^<\/?[a-zA-Z]/.test(text)) { push("tag", text); tag() }
    else push("", text)
  }
  return out
}

function span(kind, children) {
  if (!kind) return children
  const element = document.createElement("span")
  element.className = `tok-${kind}`
  element.append(...children)
  return [ element ]
}

// Renders source into target, one block per line numbered from firstLine, with the bytes of change marked.
export function renderCode(target, source, { change = null, firstLine = 1 } = {}) {
  const { start, end } = change ?? { start: -1, end: -1 }
  const rows = []
  let row = null
  let offset = 0

  const addLine = () => {
    const element = document.createElement("span")
    element.className = "demo-code__line"
    const number = document.createElement("span")
    number.className = "demo-code__number"
    number.textContent = firstLine + rows.length
    const code = document.createElement("span")
    element.append(number, code)
    rows.push(element)
    row = code
  }

  // A piece of a token on one line, with the part inside the change wrapped in a mark.
  const addPiece = (kind, text) => {
    const from = Math.max(start, offset) - offset
    const to = Math.min(end, offset + text.length) - offset
    const parts = start >= 0 && from < to
      ? [ text.slice(0, from), Object.assign(document.createElement("mark"), { textContent: text.slice(from, to) }), text.slice(to) ]
      : [ text ]
    if (parts.length > 1) row.parentElement.classList.add("demo-code__line--changed")
    row.append(...span(kind, parts))
  }

  addLine()
  for (const { kind, text } of tokens(source.replace(/\n$/, ""))) {
    text.split("\n").forEach((piece, index) => {
      if (index > 0) { offset += 1; addLine() }
      if (piece) addPiece(kind, piece)
      offset += piece.length
    })
  }
  target.replaceChildren(...rows)
}
