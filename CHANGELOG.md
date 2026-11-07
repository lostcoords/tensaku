# Changelog

## Unreleased

- Herb source stamps on every ERB element in development, through ReActionView's ERB interception and
  Herb's `SourceAttributionVisitor`. Production keeps Erubi.
- Overlay with a corner button and Alt+Shift+T: hover to see sources, copy references with the
  partial chain, Stimulus controller and Turbo Frame.
- Notes on elements, text selections and areas, stored in `tmp/tensaku/notes/`, with pins and a notes
  panel. Agents read them as files, through the MCP endpoint, from the clipboard or with the Claude
  Code skill.
- In-place editing of template text and attributes, translations (with other locales) and Markdown
  blocks from producers, written back as byte splices with a stale-file check and one-step undo.
- Edit mode outlines only elements with text written in the template, asked once from `POST /editable`.
  Text that all comes from Ruby (`<%= %>`) is not outlined.
- The overlay has one look on light and dark pages: a dark toolbar of drawn tools (highlighter to select,
  red pen to edit, sticky-note pad for notes) with tooltips, a dark element menu, notes on Post-it
  paper with a folded corner, and round pins that turn green with a drawn check when resolved. The page
  cursor shows the selected tool. Motion is off with `prefers-reduced-motion`.
- Notes can be edited from their card. An edited note goes back to `open` and loses the old reply.
- A `working` status and the `start_note` MCP tool, so the page shows when an agent picks a note up.
  `GET /notes` returns `agent.connected`, true for 20 seconds after any MCP call, and the toolbar shows
  it as a green light. The overlay polls the notes every four seconds while the tab is visible.
- Shift-click in select mode picks several elements for one note.
- Toolbar buttons to hide the pins and to delete the page's notes (after a second click).
- Arrow keys move the select-mode highlight through stamped elements; Enter opens the menu; Cmd/Ctrl+C
  copies the highlighted element's reference.
- Notes keep a thread (`thread`, with `from` and the agent's name). `reply_to_note` adds an agent
  message; answering a question from the page adds yours. Notes can move to another element
  (`PATCH /notes/:id` with `targets`), and the card says when a note's element is gone.
- MCP `initialize` returns an `Mcp-Session-Id`; the page names connected agents from `clientInfo`.
- The notes panel shows every page's notes; `GET /notes.md?format=short` gives one line per note.
- A note on selected text keeps the phrase marked on the page.
- Toasts, and optional browser notifications, when an agent starts, answers or resolves a note.
- Whole Markdown lists can be edited as source.
- Open in editor (`GET /editor`), through Rails' `ActiveSupport::Editor` and `RAILS_EDITOR`.
- Edit history for the saves made since the page loaded, and settings: copy format, notifications, a
  compact corner button.
- The editor takes the page's background, text colour and type and sits over the element, with its
  status bar floating below in the toolbar's dark material.
- Page update after a save: same-source nodes right away, then refetch and idiomorph.
- `bin/rails generate tensaku:install`.
