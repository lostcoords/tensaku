# Notes for agents

Every note records the file and line of each element it points at, so an agent can go straight to the source.

```json
{
  "id": "a7f3",
  "url": "/about",
  "comment": "tighten this, and the heading is wrong",
  "targets": [
    { "kind": "element", "file": "app/views/pages/_hero.html.erb", "range": "4:3-4:40", "tag": "h1", "text": "About me" }
  ],
  "status": "open",
  "reply": null
}
```

## Four ways to read them

- **Files**: `tmp/tensaku/notes/*.json`.
- **MCP**: `http://localhost:3000/__tensaku/mcp`, over Streamable HTTP. The generator adds it to `.mcp.json`.
- **Clipboard**: copy one note or all open notes as Markdown from the page, for any chat.
- **Claude Code skill**: `.claude/skills/tensaku/SKILL.md` explains how to find, act on and resolve notes.

## MCP tools

| Tool | Does |
|---|---|
| `list_notes` | Lists notes by status: `open`, `working`, `question`, `resolved`, `active` or `all` |
| `get_note` | Returns one note |
| `start_note` | Marks a note as being worked on; the pin shows it |
| `resolve_note` | Marks a note resolved, with a reply for the person |
| `ask_question` | Asks the person something; the question shows on the page |
| `reply_to_note` | Adds a message to the note's thread without changing its status |
| `watch_notes` | Waits up to 300 seconds for new or changed notes |
| `current_selection` | Returns the element last clicked in select mode |

`watch_notes` holds a server thread while it waits.

`initialize` returns an `Mcp-Session-Id`. A client that sends it back is named on the page by its `clientInfo` title or name, and its messages carry that name. Requests without it work the same.
