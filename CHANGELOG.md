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
- Page update after a save: same-source nodes right away, then refetch and idiomorph.
- `bin/rails generate tensaku:install`.
