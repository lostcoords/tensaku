// The mark of the coding agent behind an MCP session, from the name its client sent (clientInfo), such
// as "Claude Code" or "cursor-vscode". The marks come from Simple Icons (CC0). A client without one
// (Codex: Simple Icons has no OpenAI mark) gets the paper plane.

import { type SimpleIcon, siClaude, siCline, siCursor, siGithubcopilot, siGooglegemini, siOpencode, siWindsurf, siZedindustries } from "simple-icons"
import { icon } from "./icons"

const CLIENTS: [RegExp, SimpleIcon][] = [
  [/claude/i, siClaude],
  [/cursor/i, siCursor],
  [/gemini/i, siGooglegemini],
  [/opencode/i, siOpencode],
  [/copilot/i, siGithubcopilot],
  [/windsurf/i, siWindsurf],
  [/\bzed\b/i, siZedindustries],
  [/cline/i, siCline],
]

// A brand colour too dark to read on the tray (Cursor's black) draws in the text colour instead.
function readable(hex: string) {
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 90
}

export function clientIcon(name: string): SVGSVGElement {
  const brand = CLIENTS.find(([pattern]) => pattern.test(name))?.[1]
  if (!brand) return icon("plane")
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("class", "client")
  svg.setAttribute("viewBox", "0 0 24 24")
  svg.setAttribute("aria-hidden", "true")
  svg.setAttribute("focusable", "false")
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
  path.setAttribute("d", brand.path)
  svg.append(path)
  if (readable(brand.hex)) svg.style.color = `#${brand.hex}`
  return svg
}
