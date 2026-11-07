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
- The editor takes the page's background, text colour and type and sits over the element, with its
  status bar floating below in the toolbar's dark material.
- Page update after a save: same-source nodes right away, then refetch and idiomorph.
- `bin/rails generate tensaku:install`.
