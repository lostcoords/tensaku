# Architecture

Tensaku has three parts: an overlay in the browser, endpoints in your Rails dev server, and `tensaku mcp`, a process each coding agent starts for itself. They share one SQLite database in your user data folder, and wake each other through sockets when something changes.

After reading this page, you will know:

- Which processes run and what each one does.
- What happens when you edit text, leave a note, and when an agent works on it.
- Where Tensaku keeps its data, and who reads and writes it.

## The parts

```
 Browser tab                         Rails dev server (development only)            Your app's files
┌──────────────────────────┐        ┌──────────────────────────────────────┐       ┌───────────────────────────┐
│ Your page                │        │ ReActionView + Herb                   │       │ app/views, app/components │
│  stamped elements        │◀───────│  render templates, stamp elements     │◀──────│ config/locales            │
│  (data-herb-debug-*)     │  HTML  │  with their file and position         │ read  │ Markdown (producers)      │
│                          │        │                                       │       └─────────────▲─────────────┘
│ Tensaku overlay          │        │ Tensaku::Middleware                   │                     │ byte splices,
│ (shadow DOM)             │        │  adds the overlay script and the      │                     │ under write.lock
│  toolbar, editor, pins,  │        │  token to each HTML page              │                     │
│  notes panel, Agents     │        │                                       │                     │
│                          │  JSON  │ Tensaku::Endpoints  /__tensaku/*      │─────────────────────┘
│                          │───────▶│  /source /text /attribute /translation│
│                          │        │  /markdown /notes /editor /selection  │       ┌───────────────────────────┐
│                          │ events │  /events (one held connection)        │──────▶│ tensaku.sqlite3           │
│                          │◀───────│                                       │◀──────│ (your user data folder)   │
└──────────────────────────┘        └──────────────────▲───────────────────┘       │  projects  notes          │
                                                        │ ring                      │  messages  agents         │
 Coding agent (one per terminal)     tensaku mcp (one per agent session)            │  selections  changes      │
┌──────────────────────────┐        ┌───────────────────▼──────────────────┐       │                           │
│ Claude Code, Codex,      │ stdio  │ JSON-RPC over stdin and stdout        │──────▶│                           │
│ Cursor, Gemini CLI,      │───────▶│ loads Tensaku, not your app           │◀──────│                           │
│ OpenCode                 │◀───────│ list, start, resolve, watch notes     │       └───────────────────────────┘
│                          │        │ checks in every 5 s                   │
└──────────────────────────┘        └──────────────────────────────────────┘
                                     /tmp/tensaku-UID/<app>/*.sock: one socket per waiting
                                     process; a writer rings them all after it commits
```

| Part | Runs in | Does |
|---|---|---|
| Overlay | The browser, inside a shadow root | Selection, the text editor, pins, the notes panel, the Agents popover. Compiled from `app/javascript/tensaku/` into one script. |
| Middleware | The dev server | Adds the overlay script and a `<meta name="tensaku">` tag with the token to HTML pages, and sends `/__tensaku/*` to the endpoints. |
| Endpoints | The dev server | Describe and edit the source behind an element, and read and write notes. Loopback only, with the token. |
| `tensaku mcp` | Its own process, started by the agent | The MCP server. Reads and writes notes in the database, without Rails. |
| `tensaku notes` | A short process you or an agent runs | The same operations as the MCP tools, from a shell. |
| The database | `tensaku.sqlite3` in your user data folder | Every app's notes, the agents connected to them, each tab's selection, and a log of changes. |
| The doorbell | Unix sockets in `/tmp/tensaku-UID/` | Wakes the processes waiting for a change, so none of them polls. |

Nothing of this loads in test or production. See [Safety and limits](/safety/).

## Editing text

```
 overlay                         dev server                               files
    │  GET /source?stamp=…            │                                      │
    │────────────────────────────────▶│  Herb parses the file, finds the     │
    │                                 │  element at the stamp, returns its   │
    │◀────────────────────────────────│  pieces (text, Ruby, child elements) │
    │  you edit the text pieces       │                                      │
    │  POST /text {start,end,original,text}                                  │
    │────────────────────────────────▶│  lock ─ re-read ─ bytes still equal  │
    │                                 │  original? ─ splice ─ write ────────▶│
    │◀────────────────────────────────│  the changed lines                   │
    │  updates matching text, then refetches the page and morphs it          │
```

A save replaces only the bytes of the text you changed. If the file changed since the page rendered, the save is refused. Translations and Markdown work the same way, through `/translation` and `/markdown`. Source edits take `tmp/tensaku/write.lock` in the app, a file lock separate from the database. See [Editing text](/editing/).

## Notes and agents

```
 overlay              dev server              tensaku.sqlite3            tensaku mcp              agent
    │ POST /notes          │                         │                        │                      │
    │─────────────────────▶│ insert, in a write ────▶│ note: open, sent_at    │                      │
    │                      │ transaction             │ change #41             │    watch_notes       │
    │                      │── ring ─────────────────┼───────────────────────▶│◀─────────────────────│
    │                      │                         │ claim in one ◀─────────│ wakes, reads changes │
    │                      │                         │ transaction: owner,    │ after the last seen  │
    │                      │                         │ delivered_at           │─────────────────────▶│
    │                      │                         │                        │    start_note        │
    │                      │                         │ working ◀──────────────│◀─────────────────────│
    │                      │                         │                        │    edits your code   │
    │                      │                         │                        │    resolve_note      │
    │                      │                         │ resolved ◀─────────────│◀─────────────────────│
    │ ◀── "changed" ───────│◀── ring ────────────────┼────────────────────────│                      │
    │ GET /notes           │                         │                        │                      │
    │─────────────────────▶│ reads the notes ◀───────│                        │                      │
    │ green pin, toast     │                         │                        │                      │
```

- **New for agents.** A note is new for agents when you save it, and again when you edit it, answer it or reopen it: its `sent_at` is set.
- **Claiming.** `watch_notes` claims the new notes in the same write transaction that finds them, so a note goes to one agent session. Once a session has listened, the answer of any Tensaku tool claims and includes new notes too. A session working on a note leaves new ones to a listening session with nothing to do.
- **Assigning.** A note assigned to a session from the page's **Assign to** menu is that session's from the start, as if it had claimed it, and only that session's `watch_notes` hands it over. Assigning a note in progress takes it back: it is open again, and its old session's `resolve_note` is refused.
- **Ownership.** The note stays with that session while its process runs. Changes you request on it go back to the same session. When the session quits or its process is gone, any session can take the note, and the page and `list_notes` say that its session stopped.
- **Agents on the page.** Each `tensaku mcp` process checks in every five seconds, and holds a lock on a file named after its session in `sessions/` next to the database while it runs. The operating system drops the lock when the process ends, however it ends, so a session is running exactly while its lock is held; a process id the system reuses after a crash can't keep a note stuck. The page counts an agent as connected while it checked in within 20 seconds and its lock is held, and shows it as listening while a `watch_notes` call waits. Each check-in carries a fingerprint of Tensaku's code, and the page marks an agent whose code is older than the files on disk.
- **Starting before resolving.** `resolve_note` refuses a note that isn't `working`, so an agent has to call `start_note`, which claims the note, before it can resolve it.
- **Change events.** Every write adds a row to `changes`. The dev server keeps one connection open per tab on `/__tensaku/events`, and sends `changed` when a write rings its socket, and the page then loads the notes. A waiting process also checks every ten seconds, for an agent that stopped checking in. The page polls every four seconds only while its connection is down.

No part of this wakes an agent. MCP lets an agent call Tensaku, not the other way round, so a note reaches an agent that is waiting in `watch_notes` or calling Tensaku's tools. See [Notes](/notes/).

## Where the data lives

| What | Where | Written by | Holds |
|---|---|---|---|
| `tensaku.sqlite3` | Your user data folder, or `TENSAKU_HOME` | Dev server, `tensaku mcp`, `tensaku notes` | Every app's notes and threads, connected agents, selections, the change log |
| Doorbell sockets | `/tmp/tensaku-UID/<app>/` | Each waiting process | Nothing: a connection to one is the signal |
| `tmp/tensaku/write.lock` | The app | Dev server, with `flock` | The lock for source edits |
| `tmp/tensaku/token` | The app | Dev server | The token the page sends with each request, shared by Puma workers |
| `tmp/tensaku/mcp.log` | The app | `tensaku mcp` | One line per tool call: tool, duration, size, notes handed over |
| `sessions/*.lock` | Next to the database | Each `tensaku mcp` | A lock held while the session runs |

| Table | One row per |
|---|---|
| `projects` | App, by its real path, with its git remote and the page's address |
| `notes` | Note: comment, targets, status, owner session, commit, sent, delivered and archived times |
| `screenshots` | Note with a screenshot: the PNG and its size |
| `messages` | Message in a note's thread |
| `agents` | Agent session in an app: name, handle, folder, process id, listening, last call, code fingerprint |
| `selections` | Browser tab: the element last selected |
| `changes` | Write, numbered, so a reader asks for what came after the last one it saw |

The database runs in WAL mode, so readers don't wait for a writer, and every write holds SQLite's write lock from its start, so what it read is still true when it writes. A worktree or jj workspace is a folder of its own, so it has its own notes.

## Which app `tensaku mcp` serves

1. `--app PATH`, if given, once or more.
2. Otherwise the nearest directory above where the agent started it that has `config/application.rb`.
3. Otherwise every app up to two levels below that directory whose `Gemfile.lock` lists tensaku. Each note names its app, and each app's page lists the agent with the folder it runs in.
