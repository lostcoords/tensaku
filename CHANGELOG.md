# Changelog

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
- Notes can be edited from their card. An edited note goes back to `open` and loses the old reply.
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
- Toasts, and optional browser notifications, when an agent starts, answers or resolves a note.

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
