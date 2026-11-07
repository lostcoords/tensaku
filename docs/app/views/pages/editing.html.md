# Editing text

Alt-click (Option-click on a Mac) any text to edit it, in any mode. Or turn on edit mode from the toolbar: it outlines every editable text on the page, and a normal click edits.

Enter or leaving the editor saves. Shift+Enter adds a line break in Markdown. Escape cancels. After a save, a toast offers Undo.

## What can be edited

| Source | Written to |
|---|---|
| Static text in ERB views, partials, layouts, ViewComponent sidecar templates and mailer templates | The template, only the bytes of that text |
| `alt`, `title`, `placeholder`, `aria-label` and button `value` | The attribute value, keeping its quotes |
| `t()` translations, in text and attributes | The locale YAML, only the value's bytes |
| Markdown blocks: paragraphs, headings, list items and quotes | The Markdown file, inside the block's range |

Text from Ruby data (`@post.title`), the output of `form_with` or custom helpers, and DOM built by JavaScript can't be edited. They can still get notes.

## The editor shows the source

Ruby in a template shows as a locked chip, so you edit the text around it. Translations show `%{name}` interpolations as chips, and **Other locales** updates the same key in every locale at once. In Markdown, the heading hashes and list markers are locked and the rest is edited as Markdown.

Elements rendered in a loop share one stamp, so the editor says "this edits all 3 copies".

## How a save works

Every write is a splice. Tensaku re-reads the file, checks that the bytes it's about to replace are still what the page was rendered from, and replaces exactly those bytes through a temp file and a rename. YAML is never loaded and dumped, so comments, ordering and quoting stay. If the file changed since the page rendered, the edit is refused. Nothing is merged or guessed.

## How the page updates

After a save, Tensaku clears the template cache, ViewComponent's cache and I18n, updates every copy of the text on the page right away, then fetches the page again and morphs it in with idiomorph. Stimulus controllers stay connected and no Turbo visit fires.

Elements marked `data-turbo-permanent` or `data-tensaku-permanent` are left alone. On a page reached by a POST, such as a form that rendered errors, Tensaku updates the text it knows and asks you to reload.
