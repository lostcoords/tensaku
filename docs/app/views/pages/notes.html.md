# Notes

A note is a comment attached to part of a page. Use one when the change isn't a text edit: a layout problem, a wrong value from the database, a button that should do something else. You write notes on the page, and you or your coding agent act on them.

After reading this page, you will know:

- How to leave a note.
- How to use select mode and the element menu.
- How to send notes to an agent that is already running.
- How to follow a note while an agent works on it.
- Where notes are stored.
- How agents read and resolve notes.

## Leave a note

| To note | Do this |
|---|---|
| An element | Alt+Shift+click (Option+Shift+click on a Mac), in any mode. The note form opens right away. |
| Some text | Select the text, then Alt+Shift+click it. The phrase stays marked on the page. |
| An area | Alt-drag (Option-drag), in any mode, or drag in select mode. The note collects every stamped element at least half inside the area. |
| Several elements | Shift-click them in select mode, then press **N** or **Add note**. **Esc** clears them. |

The note form takes a screenshot of what the note points at, with a margin around it, as the page looked when the form opened. Untick **Screenshot** to save the note without it; the form remembers the choice. The overlay draws the screenshot from the page itself, so no browser permission is needed. It leaves out Tensaku's own overlay, and images from another origin that doesn't send CORS headers: those areas are blank. Drawing takes about half a second on a typical page, while you type. On a page with thousands of elements, the screenshot shows the element the note points at without the area around it, so it stays fast. The card shows the screenshot; click it to open it at full size. Agents get it with `get_screenshot` or `tensaku notes screenshot`.

To note something that moves, pause the page first with the pause button in the toolbar. It pauses CSS animations and transitions, Web Animations, and playing video and audio, until you press it again. Animations driven by JavaScript timers or `requestAnimationFrame` keep running.

## Notes and your agent

A saved note waits in the database until an agent checks for notes, and it is new for agents again when you edit it, answer its question or reopen it. Your agent gets Tensaku's tools from `tensaku mcp`, which it starts itself (see [connect a coding agent](/installation/#connect-a-coding-agent)). Then ask it in your own words:

| Ask your agent | It does |
|---|---|
| "Watch my Tensaku notes" | Waits with `watch_notes`. Each note you save reaches it as you write it, and it works through them until you tell it to stop. |
| "Do my Tensaku notes" | Works through the open notes once |

Each `tensaku mcp` session has a two-word name, such as amber-fox, and the page names it with its agent: **Claude Code · amber-fox**. The agent tells you the name when it starts listening, so you can tell which terminal is which. The card says **Picked up by Codex · amber-fox** once an agent has taken the note. The bottom of the notes panel says who is checking for notes. With nobody listening it says **No agent listening**, and **Connect one** opens the Agents popover.

The **Agents** button in the toolbar, a paper plane, is grey with no agent, drawn in ink while one is connected, and flying in green while one listens. A number shows when more than one is connected. Its popover lists the listening agents first, each with its folder and what it did last, such as "resolved xz5b 1 min ago" or the note it is working on. Agents that are connected but not listening fold into one line, **N more connected, not listening**, that expands. Until one listens, it has both prompts with a copy button each.

A long back-and-forth on a note shows the agent's latest message and what came after it, with **Show N earlier messages** for the rest. Agents get notes the same way from `list_notes` and `watch_notes`, so the thread doesn't fill their context, and `get_note` has the whole thread.

MCP lets an agent call Tensaku, but not the other way round, so an agent that isn't waiting in `watch_notes` reads your notes the next time you ask it to. Claude Code is the exception, with a channel.

### Claude Code: notes that start the agent

Claude Code can load an MCP server as a *channel*, which lets the server put a message into the session as if you had typed it. Start Claude Code in the app with Tensaku as a channel:

```sh
claude --dangerously-load-development-channels server:tensaku
```

`tensaku` is the server's name in `.mcp.json`, as the install generator writes it. Claude Code shows a warning about development channels at start; choose **I am using this for local development**. Tensaku then says hello in the chat, Claude confirms with `channel_ready`, and says in one line that your notes now arrive there. From then on, each note you save is claimed for that session and pushed into its chat, and Claude starts on it without being asked. Answering its question or asking for changes on a note sends the note back the same way. Notes that arrive while it works are handled after the current turn. In the Agents popover the session says **Live: notes reach its chat as you save them**.

What to know:

- Channels are a research preview in Claude Code. They need a claude.ai or Console login, and on a Team or Enterprise plan an owner has to turn channels on. The flag is ignored with `-p`.
- Notes already open when the session starts aren't pushed; Claude says how many there are.
- A session started without the flag gets no channel messages and works as before. Tensaku only pushes to a session that answered its hello, so no note is handed to a session that can't see it.
- Other agents (Codex, Cursor, Gemini CLI, OpenCode) have no such mechanism; use `watch_notes` with them.
- Checked with Claude Code 2.1.323.

### Assigning a note

A note is unassigned until an agent takes it, or until you assign it. With agents connected, the note form has an **Assign to** menu: **Anyone** (the default), or one session, listening sessions first. A note assigned to a session belongs to it from the start: other sessions don't see it in `watch_notes` or `list_notes` and can't start it, even while that session is busy with another note. The form remembers the last choice. The card says **Unassigned** or **Assigned to** a session until an agent picks the note up. With no agent connected, the **Assign to** row links to the Agents popover, which says how to connect one.

An open note's card has the same menu with an **Assign** button, to give the note to another session or back to anyone. A note in progress has it too, as **Reassign**: when you stop an agent in the middle of a note and its session keeps running, this takes the note back. The note is open again, and that session's `resolve_note` on it is refused. When an agent's process ends while it works on a note, the card says **stopped. Anyone can take it**, and the next agent that lists notes is told that part of the change may already be in the file.

A note belongs to one agent session: the one you assigned it to, the one `watch_notes` handed it to, or the one that started it. With two agents listening, the first to look takes the note, and the other never sees it. An agent that is working on a note leaves new ones to an agent that is listening with nothing to do. While its session's process runs, other sessions leave the note alone, and a request for changes on it goes back to the same session. When that session quits, or its process is gone, any agent can take the note. `list_notes` marks each active note as the session's own or as nobody's yet, and says how many notes other sessions hold. `resolve_note` refuses a note the agent didn't start, so an agent that skips `start_note` fails at the end instead of resolving quietly. Tensaku can't stop an agent from editing files before that.

## Select mode

Click the corner button and choose **Select**, or press Alt+Shift+T. Hover to see where each element comes from, and click an element for its menu. Alt-click (Option-click) opens the same menu in any mode.

| Key | Does |
|---|---|
| Arrow keys | Move the highlight to the parent, the first child or a sibling |
| Enter | Opens the menu |
| Cmd+C (Ctrl+C) | Copies the highlighted element's reference, when no text is selected |
| Esc | Closes the innermost open thing: the menu, the note from a pin, the side panel, then select mode, then the toolbar |

The menu has these items, with the key that picks each one:

| Item | Key | Does |
|---|---|---|
| **Edit text** or **Edit attributes** | E | Opens the [editor](/editing/) |
| **Edit the whole list** | L | Edits a Markdown list's source |
| **Add note** | N | Asks what should change. Select some text first to note just that text. |
| **Copy reference** | C | Copies the route, the file and line, the text, the partial chain, the Stimulus controller, the Turbo Frame and the translation key |
| **Undo** | U | Undoes this element's latest save |
| **Open in editor** | O | Opens the file at that line in the editor named by `RAILS_EDITOR` or `EDITOR`, through Rails' list of editors (VS Code, Cursor, Zed, RubyMine and others) |

## Follow up

Each note shows as a pin on the element it points at, and has one of these statuses:

| Status | Means |
|---|---|
| `open` | Waiting for an agent. |
| `working` | An agent picked it up |
| `question` | The agent asked something back. The question shows on the page. |
| `resolved` | The agent replied and the pin is green, so you can check the change |
| `declined` | The agent closed it without a change and said why. The pin is grey. |

What you do on a card, such as marking it done, reopening it, answering or assigning it, shows on the card and the pin at once, before the server answers. If the server refuses, the card and pin go back and a toast says why. An open card follows the note as the agent works on it, unless you are typing in it.

When an agent resolves a note, on this page or any other, the page fetches itself again and morphs the change in, the same way as after an edit (see [how the page updates](/editing/#how-the-page-updates)). Changed stylesheets are swapped in too. A page reached by a POST is left as it is.

Each note keeps a thread: the agent's questions and messages, and your answers. Answering a question sets the note back to `open`. So does editing the note, and its thread stays.

The dev server tells the page when the notes or the agents change, over one connection the page keeps open, so pins change as the agent works without the page asking every few seconds. If the connection drops, the page asks every four seconds until it is back. A toast says when an agent answers or resolves a note on this page. A note the agent has started on shows only on its pin. Toasts appear one at a time, at most three at once, and when more than three are waiting they become one toast that counts the changes.

### Manage notes

The **Notes** panel lists the notes on the current page. From there you can send them or copy them as Markdown. Each card has **Mark as done** (or **Reopen** once it's done), **Edit** and **Delete**. **All pages** lists the notes on every page, with a link to each.

The panel lists resolved and declined notes in a **Done** section, and **Archive done** moves them to the archive. Otherwise they move there after three days. Archived notes are kept: agents list them with `list_notes` and `status: archived`, and a note you reopen comes back.

The toolbar hides and shows the pins, and deletes every note on the page after a second click.

## Settings

The sliders button in the toolbar opens the settings panel. The settings are kept in the browser:

- **Copy notes as**: detailed (targets and thread) or one line per note.
- **Notify me**: a browser notification when an agent answers while the tab is in the background.
- **Keyboard shortcuts**: one per toolbar button. Select is Alt+Shift+T, Edit is Alt+Shift+E and Notes is Alt+Shift+N (⌥⇧T, ⌥⇧E and ⌥⇧N on a Mac). The others have none. Click a shortcut and press the new keys, with Alt, Ctrl or Cmd. Keys that another button had move to the new one. The panel also lists the keys that can't be changed, such as Alt+click.
- **Move the toolbar back to the corner**: after you dragged it somewhere else.

## Where notes live

Notes are in one SQLite database for every app on your machine, `tensaku.sqlite3` in your user data folder:

| System | Folder |
|---|---|
| macOS | `~/Library/Application Support/tensaku/` |
| Linux | `$XDG_DATA_HOME/tensaku/`, by default `~/.local/share/tensaku/` |
| Windows | `%LOCALAPPDATA%\tensaku\` |

Set `TENSAKU_HOME` to use another folder. The database stays on your machine, outside your project, so `git clean -x`, `tmp:clear` and deleting a checkout don't touch your notes. To delete every note, delete the folder.

Each app's notes are kept apart by the app's folder. A worktree or jj workspace is a folder of its own, so it starts with no notes. A note also records the commit that was checked out when you wrote it.

### When the code changes

A note remembers the file and line from when you wrote it, and the element's text. When lines move, its pin finds the element again by its tag and text in the same file. If the element's text changed too, the pin stays on an element of the same tag at the old position, or the note's card says it's gone. Delete it and write a new one on the right element.

The recorded line isn't updated, so an agent should look for the text if the line doesn't match.

## How agents read notes

An agent reads the same notes you see. Each one records the file and line of every element it points at, so the agent can go straight to the source.

```json
{
  "id": "a7f3",
  "url": "/about",
  "comment": "tighten this, and the heading is wrong",
  "targets": [
    {
      "kind": "element",
      "file": "app/views/pages/_hero.html.erb",
      "range": "4:3-4:40",
      "tag": "h1",
      "text": "About me",
      "classes": ["hero__title"]
    }
  ],
  "status": "open",
  "sent_at": "2026-11-07T18:00:00.000000Z",
  "thread": []
}
```

There are four ways to get them:

- **Command line**: `bundle exec tensaku notes` does what the MCP tools do, for an agent without MCP. `tensaku notes` lists the open notes, and `tensaku notes start ID`, `resolve ID REPLY`, `decline ID REASON`, `ask ID QUESTION`, `reply ID MESSAGE` and `watch` change them, and `screenshot ID` saves a note's screenshot as a PNG file. `tensaku help` lists them all.
- **MCP**: `bundle exec tensaku mcp`, a server the agent starts over stdin and stdout. The optional [generator](/installation/#connect-a-coding-agent) adds it to `.mcp.json` and other agents' config.
- **Clipboard**: copy a page's open notes or all open notes as Markdown from the page, for any chat.
- **Skill**: `SKILL.md` in `.claude/skills/tensaku/` and `.agents/skills/tensaku/` explains how to find, act on and resolve notes.

### Note fields

| Field | Holds |
|---|---|
| `id` | The note's id, also its file name |
| `url` | The path of the page it was written on |
| `comment` | What should change |
| `targets` | What it points at, see below |
| `rect` | For an area note, the area |
| `screenshot` | The size of the screenshot taken with the note, when there is one. `get_screenshot` returns the image. |
| `viewport` | The window size when the note was written |
| `status` | `open`, `working`, `question`, `resolved` or `declined` |
| `sent_at` | When the note was last sent to an agent. Missing until it is sent. |
| `delivered_at`, `delivered_to` | When `watch_notes` last handed the note to an agent, and which one |
| `commit` | The commit checked out when the note was written, when the app is in a git repository |
| `archived_at` | When the note moved to the archive |
| `agent`, `session` | The agent session the note belongs to: its name and handle, and the id of its `tensaku mcp` process |
| `thread` | The questions, answers and messages |
| `created_at`, `updated_at` | Timestamps |

Each target has a `kind`, a `file` and a `range`:

| `kind` | Points at |
|---|---|
| `element` | An element. `range` is `line:column-line:column`, 1-based. |
| `text` | Text the person selected |
| `translation` | An I18n key, with `key` and `locale`. `range` is the line of the key. |
| `markdown` | A Markdown source block |

Targets also carry the `tag`, the `text`, the element's own CSS `classes` and, in `context`, the `partials`, the Stimulus `controller` and the Turbo `frame`. An element rendered in a loop has one source position for every copy. Text from Ruby (`<%= @post.title %>`) points at the ERB expression, and the data itself lives elsewhere.

### MCP tools

| Tool | Does |
|---|---|
| `list_notes` | Lists notes, optionally for one `url`. `status` is `open`, `working`, `question`, `resolved`, `active` (the default: open, working or question) or `all`. |
| `get_note` | Returns one note |
| `get_screenshot` | Returns the note's screenshot as a PNG image |
| `start_note` | Marks a note as being worked on; the pin shows it, and the note becomes this session's. Fails when the note belongs to another running session. |
| `resolve_note` | Marks a note resolved, with a reply for the person |
| `decline_note` | Closes a note without a change, with the reason |
| `ask_question` | Asks the person something; the question shows on the page |
| `reply_to_note` | Adds a message to the note's thread without changing its status |
| `watch_notes` | Waits for notes you save: 60 seconds by default, up to 300 with `timeout_seconds` |
| `channel_ready` | Claude Code only: confirms that the Tensaku channel reaches the session, with the code from its hello |
| `current_selection` | Returns the element last clicked in select mode |

`watch_notes` waits for open notes sent after `since`, woken as soon as one is saved, and the page shows the agent as listening meanwhile. Its answer ends with a `checked_at` line to pass as `since` on the next call, so no note is missed or passed on twice. `list_notes` lists notes whether they were sent or not. Both cut a long thread down to the agent's latest message and what came after it.

Once an agent has called `watch_notes`, the answer of any other tool includes the notes sent since it last looked, already claimed for it, so it doesn't have to wait in `watch_notes` while it works: a follow-up you send reaches it at its next Tensaku call. An agent that never called `watch_notes` gets only the ids of those notes. After the agent has used `watch_notes`, `resolve_note` answers "Call watch_notes to keep listening."

`tensaku mcp` writes one JSON line per tool call to `tmp/tensaku/mcp.log`: the session, the tool, how long it took in milliseconds, the size of the answer and the notes it handed over. Past 1 MB it moves to `mcp.log.1`.

`start_note`, `resolve_note`, `decline_note`, `ask_question` and `reply_to_note` answer with one line. The tool answers are text only, with no `structuredContent`.

### The MCP server

`tensaku mcp` loads Tensaku, Active Support and SQLite, not your app, and reads and writes the same database as the dev server. The dev server doesn't have to be running, and no port is configured.

It serves the app that contains the directory the agent started it in. Started in a directory that isn't inside an app, such as the root of a monorepo, it serves every app up to two levels below that lists tensaku in its `Gemfile.lock`, and each note names its app. Each of those apps' pages lists it, with the folder it runs in. `--app PATH` picks an app and can be given more than once.

Each checkout has its own notes, so an agent in a second worktree sees that worktree's notes, whatever port its server runs on.

Nothing polls. A process that waits for notes, a page's connection to the dev server or a `watch_notes` call, listens on a Unix socket in `/tmp/tensaku-UID/`, and whoever saves a change rings each socket once the change is in the database. A waiting process also checks every ten seconds, for an agent that stopped without saying so. Where Unix sockets aren't available, it checks every second instead. Note links use the address you opened the page at, which the dev server records when the page loads.

While it runs, the page shows the agent as connected, named by the `clientInfo` it sent at `initialize` and a two-word handle from its session id that no other connected session of the app has, with the directory it runs in, its last tool call and the notes it works on. Its messages carry that name.
