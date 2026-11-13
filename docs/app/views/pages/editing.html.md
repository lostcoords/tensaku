# Editing text

Click text on the page, change it, and Tensaku writes the change to the source file and updates the page without a reload.

After reading this page, you will know:

- How to open the editor and save.
- What can and can't be edited.
- What the editor shows for Ruby, translations and Markdown.
- How a save works and how the page updates.

## Open the editor

There are two ways:

- <kbd>alt+click</kbd> any text, in any mode, then press <kbd>e</kbd> or <kbd>enter</kbd>, or choose **Edit text**. While you hold the key, the cursor changes and the element under it is highlighted.
- **Edit mode.** Click the corner button and choose **Edit**. Every editable text on the page is outlined, and a normal click edits it.

The editor sits over the text in the page's own colours and type, with its file, Cancel and Save in a bar below.

## Save or cancel

| Key | Does |
|---|---|
| <kbd>enter</kbd> | Saves |
| <kbd>shift+enter</kbd> | Adds a line break, in Markdown |
| <kbd>escape</kbd> | Cancels |
| Clicking outside the editor | Saves |

After a save, a toast offers **Undo**, and the message at the bottom of the page shows the file and line, with the old and new text of the lines that changed. It shows up to three changed lines, then a count of the rest.

Every save in the tab can be undone and redone:

| To | Do this |
|---|---|
| Undo the latest save | <kbd>mod+z</kbd>, or **Undo** on its toast |
| Redo the latest undone save | <kbd>mod+shift+z</kbd> (also <kbd>ctrl+y</kbd> outside Apple platforms), or **Redo** on the undo's toast |
| Undo an older save | **Undo** next to it in the toolbar's **Edit history** |
| Undo an element's latest save | **Undo** in the element's menu (<kbd>u</kbd>) |

The keys work while nothing is being typed in, so a field on your page and Tensaku's own editor keep their usual undo. A new save clears what can be redone. The history belongs to the browser tab and survives a reload. Each undo and redo checks that the file still has the text it expects, and is refused if the file changed since, like any save. A translation saved in several locales from one editor is one entry, and one undo reverts every locale.

## What can be edited

| Source | Written to |
|---|---|
| Static text in ERB views, partials, layouts, ViewComponent sidecar templates and mailer templates | The template, only the bytes of that text |
| `alt`, `title`, `placeholder`, `aria-label` and button `value` | The attribute value, keeping its quotes |
| `t()` translations, in text and attributes | The locale YAML, only the value's bytes |
| Markdown blocks: paragraphs, headings, list items, quotes and whole lists | The Markdown file, inside the block's range |

The file has to be in the [writable paths](/configuration/). By default those are `app/views`, `app/components` and `config/locales`.

Text from Ruby data (`@post.title`), the output of `link_to`, `form_with` or custom helpers, and DOM built by JavaScript can't be edited. They can still get [notes](/notes/). [Limits](/safety/#limits) has the full list.

## What the editor shows

The editor shows the source, not the rendered text.

- **Ruby** shows as a locked chip, so you edit the text around it. In `Hello <%= user.name %>!` you edit `Hello ` and `!`.
- **Child elements** show as they look on the page. A line break breaks, an element's text is dimmed and opens its own editor when you click it, and an element without text, like an icon, is a small mark.
- **Translations** show `%{name}` interpolations as chips. **Other locales** updates the same key in every locale at once.
- **Markdown** has its heading hashes and list markers locked, and the rest is edited as Markdown. Tables and code blocks only get notes.
- **Whole lists** open with **Edit the whole list**, in a list item's menu. It edits the list's source with its markers. <kbd>enter</kbd> starts a new line and <kbd>mod+enter</kbd> saves.
- **Loops** share one source position, so the editor says "this edits all 3 copies".

## How a save works

Every write is a splice:

1. Tensaku re-reads the file.
2. It checks that the bytes it's about to replace are still what the page was rendered from. If the file changed since the page rendered, the edit is refused. Nothing is merged or guessed.
3. It replaces exactly those bytes, through a temp file and a rename.

YAML is never loaded and dumped, so comments, ordering and quoting stay.

## How the page updates

After a save, Tensaku:

1. Clears the template cache, ViewComponent's cache and I18n.
2. Updates every copy of the text on the page.
3. Fetches the page again and morphs it in with idiomorph.

Stimulus controllers stay connected, no Turbo visit fires, and form controls you changed keep their values.

Elements marked `data-turbo-permanent` or `data-tensaku-permanent` are left alone. On a page reached by a POST, such as a form that rendered errors, Tensaku updates the text it knows and asks you to reload.
