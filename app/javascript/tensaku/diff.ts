import { div, h } from "./ui"

// The lines a save changed, as the server read them from the file before and after the write.
export interface Diff { line: number; removed: string[]; added: string[] }

const CONTEXT = 26
const MAX_LINES = 3

function sharedEnds(before: string, after: string) {
  let prefix = 0
  while (prefix < before.length && before[prefix] === after[prefix]) prefix++
  let suffix = 0
  while (suffix < before.length - prefix && suffix < after.length - prefix && before[before.length - 1 - suffix] === after[after.length - 1 - suffix]) suffix++
  // Widened so the mark covers whole words.
  while (prefix > 0 && /\w/.test(before[prefix - 1])) prefix--
  while (suffix > 0 && /\w/.test(before[before.length - suffix])) suffix--
  return { prefix, suffix }
}

// One side of a changed line: the changed words, with a little of the line around them, cut at a space.
function row(sign: "-" | "+", line: string, { prefix, suffix }: { prefix: number; suffix: number }) {
  const end = line.length - suffix
  const head = prefix > CONTEXT ? `…${line.slice(prefix - CONTEXT, prefix).replace(/^\S*\s/, "")}` : line.slice(0, prefix).trimStart()
  const tail = suffix > CONTEXT ? `${line.slice(end, end + CONTEXT).replace(/\s\S*$/, "")}…` : line.slice(end)
  return div(`diff-row ${sign === "-" ? "removed" : "added"}`, h("span", { className: "diff-sign" }, sign), head, h("mark", {}, line.slice(prefix, end)), tail)
}

export function diffRows({ removed, added }: Diff) {
  const count = Math.max(removed.length, added.length)
  const rows: HTMLElement[] = []
  for (let index = 0; index < Math.min(count, MAX_LINES); index++) {
    const ends = sharedEnds(removed[index] ?? "", added[index] ?? "")
    if (removed[index] !== undefined) rows.push(row("-", removed[index], ends))
    if (added[index] !== undefined) rows.push(row("+", added[index], ends))
  }
  if (count > MAX_LINES) rows.push(div("diff-more", `${count - MAX_LINES} more ${count - MAX_LINES === 1 ? "line" : "lines"} changed`))
  return div("diff", ...rows)
}
