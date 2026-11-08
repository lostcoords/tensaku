# Attributes and producers

The overlay reads only these attributes, so any renderer that sets them works with it.

| Attribute | Set by | Meaning |
|---|---|---|
| `data-herb-source="path:line:col"` | Herb | The element's open tag position, 1-based |
| A marker inside translated strings | Tensaku's I18n backend | Locale and key, stripped by the overlay |
| `data-tensaku-group` | The app | Widens the highlight and the edit target to this element |
| `data-md-source="path:line:col-line:col"` | A Markdown producer | The block's Markdown source range: 1-based lines, byte columns, end inclusive, path relative to the app root |
| `data-tensaku-permanent` | The app | The morph after a save leaves this element alone |
| `data-tensaku-request` on `<meta name="tensaku">` | Tensaku | The request method, so the overlay knows whether it can fetch the page again |

## Translation markers

In development, while a controller handles an HTML request, the I18n backend wraps each translated string in an invisible marker: U+2063, the locale and key encoded with zero-width characters, then U+2063. The overlay strips the markers when the page loads. The middleware strips them from `<script>`, `<style>` and non-HTML responses.

## Kiln

From Kiln 0.1.3, [Kiln](https://github.com/davafons/kiln)'s content layer adds `data-md-source` to `p`, `h1` to `h6`, `ul`, `ol`, `li`, `blockquote`, `pre`, `table` and `hr` once the app turns it on, for example with `Kiln::Content.source_positions = Rails.env.development?` in an initializer. Kiln builds fail if any `data-herb-*`, `data-tensaku-*` or `data-md-source` attribute reaches the output.

Tensaku edits the text of paragraphs, headings, list items and quotes, and whole lists as source. Code blocks, tables and rules only get notes.

Kiln's content directory isn't writable by default. Add `content/` to `writable_paths`, and the directory of any file rendered with `Kiln::Content.file`.
