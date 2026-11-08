# Editing text

Alt-click (Option-click on a Mac) any text to edit it, in any mode. Or turn on edit mode from the toolbar: it outlines every editable text on the page, and a normal click edits.

The editor sits over the text in the page's own colours and type, with its file, Cancel and Save in a bar below.

Enter or leaving the editor saves. Shift+Enter adds a line break in Markdown. Escape cancels. After a save, a toast offers Undo, and the toolbar's **Edit history** lists the saves made since the page loaded. Each element can undo its latest edit from there.

## What can be edited

| Source | Written to |
|---|---|
| Static text in ERB views, partials, layouts, ViewComponent sidecar templates and mailer templates | The template, only the bytes of that text |
| `alt`, `title`, `placeholder`, `aria-label` and button `value` | The attribute value, keeping its quotes |
| `t()` translations, in text and attributes | The locale YAML, only the value's bytes |
| Markdown blocks: paragraphs, headings, list items, quotes and whole lists | The Markdown file, inside the block's range |

Text from Ruby data (`@post.title`), the output of `form_with` or custom helpers, and DOM built by JavaScript can't be edited. They can still get notes.

## The editor shows the source

Ruby in a template shows as a locked chip, so you edit the text around it. A child element shows as it looks on the page: a line break breaks, an element's text is dimmed and opens its own editor when you click it, and an element without text, like an icon, is a small mark. Translations show `%{name}` interpolations as chips, and **Other locales** updates the same key in every locale at once. In Markdown, the heading hashes and list markers are locked and the rest is edited as Markdown. **Edit the whole list**, in a list item's menu, edits the list's source with its markers. There Enter starts a new line and Cmd+Enter (Ctrl+Enter) saves. Tables and code blocks only get notes.

Elements rendered in a loop share one stamp, so the editor says "this edits all 3 copies".

## How a save works

Every write is a splice. Tensaku re-reads the file, checks that the bytes it's about to replace are still what the page was rendered from, and replaces exactly those bytes through a temp file and a rename. YAML is never loaded and dumped, so comments, ordering and quoting stay. If the file changed since the page rendered, the edit is refused. Nothing is merged or guessed.

After a save, the message at the bottom of the page shows the file and line, with the old and new text of the lines that changed. The server reads those lines from the file before and after the write. Up to three changed lines are shown, then a count of the rest.

## How the page updates

After a save, Tensaku clears the template cache, ViewComponent's cache and I18n, updates every copy of the text on the page right away, then fetches the page again and morphs it in with idiomorph. Stimulus controllers stay connected and no Turbo visit fires.

Elements marked `data-turbo-permanent` or `data-tensaku-permanent` are left alone. On a page reached by a POST, such as a form that rendered errors, Tensaku updates the text it knows and asks you to reload.
