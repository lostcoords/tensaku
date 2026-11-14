# Changelog

## 0.2.3 (2026-11-14)

### Translations

- Translation markers are only added while a template renders. Text translated in a controller
  action, such as a flash message, is plain text again: it can't be traced back to its key from the
  page, but code that measures, compares or stores it no longer sees a marker.

- A translation that names an asset, such as `image_tag t("hero.image")` with a screenshot per
  locale, resolves again. Its marker made the asset lookup fail with `Propshaft::MissingAssetError`.
- A page no longer freezes when the app cuts a translated string short, such as a title truncated
  for `og:title`. The cut marker could not be stripped, the overlay wrote the same value back, and
  its observer saw that write as a new change, forever. Cut markers are now stripped, and an
  unchanged value is never written.
- Markers no longer reach your data. A translated string assigned to a model attribute, such as a
  default category name made in a callback, loses its marker, so it is validated and saved as plain
  text. Before, a length validation could fail, or the marker was stored in the database.
- A blank translation gets no marker, so `t("step.subtitle").present?` stays false and the page
  doesn't render an empty element that only exists in development.

## 0.2.2 (2026-11-14)

### Overlay

- Phones: the open toolbar fits on screens up to 520px wide (it used to stop at 420px, so on a 430px
  phone the first tools were off the left edge), and also when the dock was dragged away from the
  corner. The text editor's bar shortens the file name so Cancel and Save stay on screen. Dragging the
  corner button moves the dock instead of scrolling the page. Touch screens no longer show keyboard
  shortcuts in the element menu and note form, or leave a tool's tip up after a tap.

## 0.2.1 (2026-11-14)

### Agents

- An agent takes fewer turns per note. Claude Code loads the tools of the work loop (`list_notes`,
  `start_note`, `resolve_note`, `decline_note`, `ask_question`, `watch_notes`, `channel_ready`) up front
  instead of behind its tool search. Notes from the MCP tools and `tensaku notes` give absolute file
  paths. `resolve_note`, `decline_note` and `ask_question` end with how many open notes are left. With
  Claude Haiku, one note went from 7 or 8 tool calls to 5, and from about 8.5 to 4.5 seconds.
- A note handed to an agent session, by `watch_notes`, the Claude Code channel or with another tool's
  answer, is started for it at once: the pin shows the agent on it, and the agent doesn't call
  `start_note`. A note an agent finds with `list_notes` still needs `start_note`, so two sessions can't
  both work on it.
- While an agent works on a note, the page reloads itself whenever the app's files change, so each edit
  shows as it lands instead of when the agent resolves the note. The dev server looks at the files
  under `app/` and `config/locales/` four times a second, only while a note is being worked on.

## 0.2.0 (2026-11-14)

Upgrading from 0.1.0: rerun `bin/rails generate tensaku:install` to replace the `.mcp.json` entry with
`bundle exec tensaku mcp`. Notes from 0.1.0 aren't carried over. `config.notes_path`, `config.shortcut`
and `config.prune_after` are gone; `config.archive_after` replaces `prune_after`.

### Editing

- Undo and redo: every text save in the tab can be undone, newest first or from the edit history, and
  redone, with Cmd/Ctrl+Z and Cmd/Ctrl+Shift+Z (Ctrl+Y) or from the toasts. The history survives a
  reload. A new save clears what can be redone. A translation saved in several locales at once is undone
  in all of them.
- The editor shows child elements as they look on the page instead of as code. `<br>` breaks the line,
  an element's text keeps its style, dimmed, and opens that element's editor on a click, and an element
  without text is a small mark. Whitespace between elements is no longer an editable field.
- Escape closes one thing at a time, the innermost first: it leaves a field in Tensaku's panels, then
  closes the popover, the element menu, the note opened from a pin, the settings or notes panel, turns
  select or edit mode off, and last folds the toolbar away. A focused field of the page keeps its own
  Escape.
- Locked chips have a fixed size, so they stay small in a heading, and long ones are cut off with an
  ellipsis.

### Agents

- The MCP server is `bundle exec tensaku mcp`, which the agent starts over stdin and stdout, in place
  of the HTTP endpoint at `/__tensaku/mcp`. It doesn't load the app, so the dev server doesn't have to
  be running and no port is configured. It serves the app that contains the agent's directory, or the
  apps below it that list tensaku in `Gemfile.lock`, or those given with `--app`. Rerun the generator
  to replace the old `.mcp.json` entry.
- The Agents popover shows each agent's mark when its client is known (Claude Code, Cursor, Gemini CLI,
  OpenCode, GitHub Copilot, Windsurf, Zed, Cline), from Simple Icons. Codex and other clients show a
  paper plane.
- `bundle exec tensaku notes` does what the MCP tools do, from a shell, for agents without MCP.
- Notes are kept in a SQLite database, `tensaku.sqlite3` in your user data folder (`TENSAKU_HOME` to
  change it), for every app and checkout on the machine, instead of JSON files in `tmp/tensaku/notes`.
  Notes from 0.1.0 aren't carried over. The `sqlite3` gem is a new dependency, loaded in development
  only. `config.notes_path` is gone.
- Notes have a `sent_at`, set when you save, edit, answer or reopen them from the page, and record the
  commit checked out when they were written. `watch_notes` returns notes sent after `since`, and a card
  says when it delivered one (`delivered_at`, `delivered_to`). A cancelled `watch_notes` stops waiting.
- Nothing polls. The page gets change events from the dev server (`GET /__tensaku/events`), and a
  process waiting for notes is woken over a Unix socket when a change is saved. The page polls only
  while its event stream is down.
- A note belongs to one `tensaku mcp` session: the one you assign it to with the note form's
  **Assign to** menu, the one `watch_notes` hands it to, or the one that starts it. Unassigned notes go
  to the first session that checks. Other sessions leave a note alone while its session's process
  runs, and a request for changes goes back to it. A card can assign an open note to another session,
  or take a note in progress back from a session that was stopped mid-work. A note whose session
  ended mid-work says so on the page and in `list_notes`. A session busy with a note leaves new ones to an idle listening session.
  `list_notes` marks each note as the session's own or nobody's yet, and `resolve_note` refuses a note
  that wasn't started. A session counts as running while its process holds a lock in the data folder,
  so a crashed agent's notes are free at once.
- Once an agent has listened, any Tensaku tool answer includes and claims the notes sent since it last
  looked, so a busy agent gets them at its next call. Other agents get the ids.
- Each session has a two-word handle, such as amber-fox, unique among the app's connected sessions,
  shown with the agent's name on the page and given to the agent to tell you.
- An Agents button in the toolbar replaces the green light: its popover lists each agent's folder,
  start time, the note it works on or its last call, listening sessions first, and what to ask an agent
  so it listens.
- Notes carry a screenshot of what they point at, taken by the page when the note form opens, without
  a browser permission. Agents get it with `get_screenshot` or `tensaku notes screenshot ID`.
  **Screenshot** in the form turns it off. The overlay bundles modern-screenshot 4.7.0 for this.
- `decline_note` closes a note without a change, with the reason in its thread. Declined notes have a
  grey pin.
- Resolved and declined notes move to an archive after `config.archive_after` (was
  `config.prune_after`, which deleted them) or with **Archive done**. `list_notes` takes
  `status: archived`, and a reopened note comes back.
- Long threads show the agent's latest message and what came after it, on the cards and in `list_notes`
  and `watch_notes`. `get_note` has the whole thread.
- Each browser tab keeps its own selection; `current_selection` returns the newest.
- The page says to restart the dev server when Tensaku's code changed since it started, and the Agents
  popover marks an agent that runs older Tensaku code.
- The notes panel has an **Archive** tab.
- Changes made on a note card show at once and go back if the server refuses them. An open card
  follows the agent's changes to its note.
- When an agent resolves a note, the page fetches itself again and morphs the change in, with changed
  stylesheets.
- Claude Code channel: in a session started with
  `claude --dangerously-load-development-channels server:tensaku`, each note you save is pushed into
  the chat and Claude starts on it without being asked. The new `channel_ready` tool confirms the
  channel works; the Agents popover shows the session as **Live**.
- `tensaku mcp` logs each tool call to `tmp/tensaku/mcp.log`: tool, duration, answer size and the
  notes handed over.
- Note links in the MCP answers and copied Markdown use the address the page was opened at.
- Note targets carry the element's `classes`, and the Markdown lists them.
- The generator sets up more agents, and no longer takes `--port`: the skill also goes in
  `.agents/skills/tensaku/` (Codex, Cursor, Gemini CLI, OpenCode and Copilot read it), `--agents`
  writes `.codex/config.toml`, `.cursor/mcp.json`, `.gemini/settings.json` and `opencode.json`, and by
  default it writes them for the agents already configured in the project.
- MCP tool answers are text only: `structuredContent` is gone, the tools that change a note answer
  with one line, and `watch_notes` ends its text with a `checked_at` line.
- The skill, the MCP instructions and the tool descriptions tell the agent to start a note before
  changing anything and to resolve it as soon as its change is made, before starting the next.
- `GET /notes.md` no longer takes `id`. The overlay's copy button was its only user.
- Notes no longer have a `reply` field, and `PATCH /notes/:id` no longer takes one. What the agent
  says is in `thread`. `resolve_note` still takes its text as `reply`.

### Install

- The generator is optional and only connects a coding agent. It no longer writes
  `config/initializers/reactionview.rb`: Tensaku turns off Herb's debug mode itself, and an app's
  initializer can still turn it on.

### Rendering

- Tensaku no longer turns on Herb's `action_view_helpers` option. With it on, Herb 0.11.2 dropped
  attributes passed as `tag.div(**attrs)` in development. Helpers such as `link_to` now render as they
  do in production and have no source stamp of their own, so a note on one points at the nearest
  stamped ancestor. The safety page shows how to turn the option back on.

### Overlay

- Note cards are simpler. The message box is gone (edit the note instead, and a question still takes an answer), and so is the copy button. The actions are unoutlined icons at the top of the card with tooltips. Source lines are grouped by file under the note, and the agent's replies sit under a ruled line.
- Notes can no longer be moved to another element, and `PATCH /notes/:id` no longer takes `targets`. A card whose element is gone says so; delete it and write a new note.
- A note card's buttons are **Mark as done** (or **Reopen**), **Edit** and **Delete**, in that order. 
- The bottom of the notes panel says which agent your notes go to. With none, **Connect one** lists the commands that start one, each with a copy button. **Copy page notes** and **Copy all open** are now **Copy page** and **Copy all**.
- The toolbar's buttons are in three groups: select and edit, notes, then pause, history and settings. The settings button has a sliders icon.
- Settings open in a side panel in place of the notes panel. Every toolbar button can have a keyboard shortcut, changed or removed in the panel for this browser: Select is Alt+Shift+T, Edit is Alt+Shift+E and Notes is Alt+Shift+N. Escape closes the panel.
- `config.shortcut` is gone. Set the shortcuts in the settings panel.
- The Compact button setting is gone.
- On a phone the toolbar's buttons are smaller, and on a screen too narrow for all of them they scroll sideways.
- The toolbar pauses the page's CSS animations and transitions, Web Animations and playing media, so you can note an element mid-animation. JavaScript timers and `requestAnimationFrame` loops keep running.
- Agent toasts appear one at a time, at most three at once. More than three waiting become one toast that counts the changes, with a button that opens the notes panel. Browser notifications follow the same rule.
- The notes panel lists resolved and declined notes in a **Done** section with an **Archive done** button. Its copy buttons are in a bar at the bottom right that stays in view while the notes scroll, and the bar is hidden when there is nothing open to copy.
- Post-its have a folded corner that joins the paper.
- Alt+Shift-click (Option+Shift-click) opens the note form on an element, in any mode.
- A note's pin sits where you clicked to write it, kept as a `point` on the target, and follows the
  element when the layout changes. Area notes, notes on several elements and notes written from the
  keyboard keep the pin at the top right.
- The corner button shows a pointer cursor, and a grabbing cursor only once a drag starts.
- The corner button and the toolbar are one pill. The button stays where it is, the logo spins and the tools unroll to its left. Clicking the button closes the toolbar, the notes panel and the current mode, so there is no separate close button. Notes moved next to the page actions, and the selected tool's circle stays centered in the bar.
- Alt-click (Option-click) opens the actions menu on any element, in any mode, instead of going straight to the editor. Edit text comes first in the menu, so Alt-click then E or Enter edits. A click outside the menu closes it and doesn't reach the page.
- Alt-drag (Option-drag) draws an area for a note, in any mode.
- Holding Alt (Option) shows the select cursor and highlights the element under the pointer until the key is released. It does nothing while you type in a field.
- A note's pin finds its element by tag and text when the file's lines have moved. Before, it showed on
  whatever was now at the old line, or on nothing.
- The corner button shows the new logo, a hanamaru, instead of the character 添.
- The message after a save shows the file, the line, and the old and new text of the lines that changed.
  Save replies carry these lines as `diff`.
- Shortcut labels follow the platform: `⌥⇧T` on Apple platforms and `Alt+Shift+T` elsewhere, and the
  note form says `⌘↵ saves` or `Ctrl+Enter saves`.

## 0.1.0 (2026-11-08)

### Editing

- Herb stamps every ERB element with its source position in development, through ReActionView's ERB
  interception and Herb's `SourceAttributionVisitor`. Production keeps Erubi.
- In-place editing of template text and attributes, translations (with other locales) and Markdown
  blocks from producers. Writes are byte splices with a stale-file check and one-step undo.
- Whole Markdown lists can be edited as source.
- Markdown blocks are read from `data-md-source="path:line:col-line:col"`, the attribute Kiln 0.1.3
  writes. Paragraphs, headings, list items, quotes and whole lists are editable; code blocks, tables and
  rules only get notes. Kiln's content directory isn't writable automatically: add it to
  `writable_paths`.
- Edit mode outlines only elements with text written in the template, asked once from `POST /editable`.
  Text that comes entirely from Ruby (`<%= %>`) isn't outlined.
- The editor takes the page's background, text colour and type and sits over the element. Its status
  bar floats below it.
- After a save, the page updates every node with the same source right away, then fetches the page
  again and morphs it in with idiomorph.
- Edit history lists the saves made since the page loaded.
- Open in editor (`GET /editor`), through Rails' `ActiveSupport::Editor` and `RAILS_EDITOR`.

### Notes

- Notes on elements, text selections and areas, stored in `tmp/tensaku/notes/`, with pins and a notes
  panel. Agents read them as files, through the MCP endpoint, from the clipboard or with the Claude
  Code skill.
- Notes can be edited from their card. An edited note goes back to `open` and keeps its thread.
- A `working` status and the `start_note` MCP tool show when an agent picks a note up. `GET /notes`
  returns `agent.connected`, true for 20 seconds after any MCP call, and the toolbar shows it as a
  green light. The overlay polls the notes every four seconds while the tab is visible.
- Notes keep a thread (`thread`, with `from` and the agent's name). `reply_to_note` adds an agent
  message, and answering a question from the page adds yours.
- Notes can move to another element (`PATCH /notes/:id` with `targets`). The card says when a note's
  element is gone.
- MCP `initialize` returns an `Mcp-Session-Id`. The page names connected agents from `clientInfo`.
- The notes panel shows every page's notes. `GET /notes.md?format=short` gives one line per note.
- A note on selected text keeps the phrase marked on the page.
- Toasts, and optional browser notifications, when an agent answers or resolves a note. A note the agent has started on shows only on its pin.

### Overlay

- A corner button and Alt+Shift+T open select mode. Hover to see sources, and copy references with
  the partial chain, the Stimulus controller and the Turbo Frame.
- Arrow keys move the select-mode highlight through stamped elements. Enter opens the menu, and
  Cmd/Ctrl+C copies the highlighted element's reference.
- Shift-click in select mode picks several elements for one note.
- Toolbar buttons hide the pins and delete the page's notes after a second click.
- Settings for the copy format, notifications and a compact corner button.
- One look on light and dark pages: a dark toolbar of drawn tools (highlighter to select, red pen to
  edit, sticky-note pad for notes) with tooltips, a dark element menu, notes on Post-it paper, and round
  pins that turn green with a drawn check when resolved. The page cursor shows the selected tool.
  Motion is off with `prefers-reduced-motion`.

### Safety and fixes

- `writable_paths` takes single files as well as directories. A file allows only that file, such as
  `../CONTRIBUTING.md` outside the app.
- The endpoints check the `Host` and `Origin` headers and refuse requests a proxy forwarded from
  another machine, so DNS rebinding or a tunnel can't reach them.
- The token goes only into successful pages and 422 form errors requested with a local `Host`, never
  into error pages or HTML fragments that scripts fetch. It's kept in `tmp/tensaku/token`, shared by
  Puma workers and across restarts.
- The script carries the page's CSP nonce and respects `SCRIPT_NAME`.
- Saves and note changes take a shared lock, so concurrent saves don't lose each other's changes.
- Apps that use `I18n::Backend::Chain` no longer fail on every `t()` call in development.
- An untouched `&nbsp;` stays `&nbsp;` after a nearby edit. CRLF files keep CRLF line endings. YAML
  anchors and tags survive an edit, and a value in a flow mapping is quoted when it needs to be.
- `watch_notes` no longer misses notes saved in the same second as its `since`. Malformed note files
  are skipped. Bad request bodies get a 422 instead of a server error.
- The toast's Undo reverts the save it belongs to. Enter while composing with an IME doesn't save.
  Values typed into the page's forms survive the refresh after a save. Translations stay editable after
  Back and Forward. A second copy of the script adds nothing.
- Select mode leaves keys in the page's own inputs alone. Every changed piece of an attribute is saved.
  Pins and outlines follow scrolling containers. A note on a repeated element pins to the matching copy.
- Herb, ReActionView and Rails are pinned to the versions Tensaku is tested with.
- The generator (`bin/rails generate tensaku:install`) reads the Gemfile through Bundler, reports an
  invalid `.mcp.json` instead of crashing, honors `--pretend` and uses the configured mount path.
