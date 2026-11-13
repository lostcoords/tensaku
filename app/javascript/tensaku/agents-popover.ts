// The Agents popover: the coding agents connected to this app, what each is doing, and how to connect
// one or have it listen.

import { icon } from "./icons"
import { type Agent, agentLabel, currentAgents } from "./notes"
import { ago, redrawPopover } from "./popover"
import { copy, div, h, toast } from "./ui"

// What an agent can be asked, in its own chat. Tensaku can't start an agent's turn, so listening is
// something the person asks for.
const PROMPTS = {
  watch: "Watch my Tensaku notes", once: "Do my Tensaku notes", install: "bin/rails generate tensaku:install",
  channel: "claude --dangerously-load-development-channels server:tensaku",
}
function copyRow(text: string, done: string) {
  return div("command", h("code", {}, text),
    h("button", { type: "button", className: "icon-button", title: "Copy", "aria-label": `Copy ${text}`, onclick: async () => { await copy(text); toast(done) } }, icon("copy")))
}
// What the agent last did, from its last tool call: "resolved xz5b 1 min ago".
const DID: Record<string, string> = { start_note: "started", resolve_note: "resolved", decline_note: "declined", ask_question: "asked on", reply_to_note: "replied on", get_note: "read", list_notes: "listed the notes", watch_notes: "checked for notes", current_selection: "read the selection" }
function lastAction(agent: Agent) {
  if (agent.working.length) return agent.working.map((note) => h("a", { className: "doing", href: note.url, title: `“${note.comment}”` }, `Working on ${note.id}: “${note.comment}”`))
  const last = agent.last
  const did = last ? `${DID[last.tool] ?? last.tool}${last.note ? ` ${last.note}` : ""} ${ago(new Date(last.at))}` : null
  const waiting = agent.channel ? "Live: notes reach its chat as you save them" : "Waiting for your notes"
  const text = agent.listening ? `${waiting}${did ? ` · ${did}` : ""}` : did ? `Last ${did}` : "No calls yet"
  return [h("span", { className: "doing" }, text)]
}
// One agent: its name and handle, the folder it runs in, and what it did last.
function agentRow(agent: Agent) {
  return div(`agent${agent.listening ? " listening" : ""}${agent.channel ? " live" : ""}${agent.working.length ? " working" : ""}`,
    div("who", h("strong", {}, agentLabel(agent)), h("span", { className: "where" }, agent.folder ?? "")),
    agent.outdated ? div("outdated", "Runs older Tensaku code. Reconnect it (/mcp in Claude Code) or restart it.") : null,
    ...lastAction(agent))
}
let idleOpen = false
export function renderAgents(): Node[] {
  const agents = currentAgents()
  const listening = agents.filter((agent) => agent.listening)
  const idle = agents.filter((agent) => !agent.listening)
  // An agent only reads notes when it calls Tensaku, so it has to be asked, in its own chat.
  const ask = (lead: string) => [
    h("p", {}, lead),
    copyRow(PROMPTS.watch, "Copied. Paste it into your agent's chat."),
    h("p", { className: "where" }, "It waits for notes and takes each one as you save it."),
    copyRow(PROMPTS.once, "Copied. Paste it into your agent's chat."),
    h("p", { className: "where" }, "It works through the open notes, then stops."),
    h("p", {}, h("strong", {}, "Claude Code, without asking: "), "start it with Tensaku as a channel, and each note you save starts it working. Experimental, and it asks you to confirm at start:"),
    copyRow(PROMPTS.channel, "Copied. Run it in the app's folder."),
  ]
  // Listeners first. The rest, connected but not listening, are one line that expands, unless they are all there is.
  const rest = listening.length && idle.length
    ? [h("button", { type: "button", className: "idle-toggle", "aria-expanded": String(idleOpen), onclick: () => { idleOpen = !idleOpen; redrawPopover() } },
        `${idle.length} more connected, not listening`), ...(idleOpen ? idle.map(agentRow) : [])]
    : idle.map(agentRow)
  return [
    h("h3", {}, "Agents", h("span", { className: "where" }, "Coding agents connected to this app. Each note goes to one of them.")),
    ...(agents.length
      ? [...listening.map(agentRow), ...rest, ...(listening.length ? [] : [div("connect", ...ask("None is listening. Agents read notes when you ask them to, so say this in your agent's chat:"))])]
      : [div("empty", "No agent connected."),
          div("connect",
            h("p", {}, h("strong", {}, "Set up once per project. "), "Run this in the app, then restart your agent. It adds Tensaku to Claude Code, Codex, Cursor, Gemini CLI and OpenCode:"),
            copyRow(PROMPTS.install, "Copied. Run it in the app, then restart your agent."),
            h("p", { className: "where" }, "Already set up? Start your agent in this project and it shows here. In Claude Code, /mcp reconnects it."),
            ...ask("Then say this in your agent's chat:"))]),
  ]
}
