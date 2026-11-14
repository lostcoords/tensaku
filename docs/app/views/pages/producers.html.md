# Attributes and producers

The overlay works from a few attributes in the page, so any renderer that sets them works with it. You only need this page to write a renderer or to change how the overlay treats part of your page.

After reading this page, you will know:

- Which attributes the overlay reads.
- How translation markers work.
- How to turn on Markdown editing with Kiln.

## Attributes

| Attribute | Set by | Meaning |
|---|---|---|
| `data-herb-source="path:line:col"` | Herb | The element's open tag position, 1-based |
| `data-md-source="path:line:col-line:col"` | A Markdown producer | The block's Markdown source range: 1-based lines, byte columns, end inclusive, path relative to the app root |
| `data-tensaku-group` | The app | Widens the highlight and the edit target to this element |
| `data-tensaku-permanent` | The app | The morph after a save leaves this element alone |
| `data-tensaku-ui` | The app | The overlay ignores this element and everything inside it |

## Translation markers

In development, while a template of an HTML page renders, the I18n backend wraps each translated string in an invisible marker: U+2063, the locale and key encoded with zero-width characters, then U+2063. Text translated in the controller action, such as a flash message, gets no marker, and neither do blank translations.

The overlay strips the markers when the page loads. The middleware strips them from `<script>`, `<style>` and non-HTML responses.

## Kiln

From version 0.1.3, [Kiln](https://github.com/davafons/kiln)'s content layer can add `data-md-source` to `p`, `h1` to `h6`, `ul`, `ol`, `li`, `blockquote`, `pre`, `table` and `hr`. Turn it on in an initializer:

```ruby
# config/initializers/kiln.rb
Kiln::Content.source_positions = Rails.env.development?
```

Kiln's content directory isn't writable by default. Add `content/` to [`writable_paths`](/configuration/), and the directory of any file rendered with `Kiln::Content.file`.

Tensaku edits the text of paragraphs, headings, list items and quotes, and whole lists as source. Code blocks, tables and rules only get notes.

Kiln builds fail if any `data-herb-*`, `data-tensaku-*` or `data-md-source` attribute reaches the output.
