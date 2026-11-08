// The card a new note brings up in the demo: what the agent gets, which no part of the page shows.

const VISIBLE_FOR = 8000
let current = null

function show(...children) {
  current?.remove()
  const card = Object.assign(document.createElement("div"), { className: "demo-card" })
  card.setAttribute("role", "status")
  card.setAttribute("data-tensaku-ui", "")
  card.append(...children)
  document.body.append(card)
  current = card
  setTimeout(() => card.remove(), VISIBLE_FOR)
}

function element(tag, className, text) {
  const node = Object.assign(document.createElement(tag), { className })
  if (text !== undefined) node.textContent = text
  return node
}

export function showNote(note) {
  const target = note.targets[0]
  const where = target?.file ? `${target.file}:${(target.range ?? "").split("-")[0]}` : "the page"
  show(element("div", "demo-card__file", "Your agent gets this note"), element("div", "demo-card__comment", note.comment), element("div", "demo-card__where", `at ${where}`))
}
