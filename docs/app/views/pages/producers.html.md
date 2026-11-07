# Attributes and producers

The overlay only reads attributes, so it doesn't care what rendered the page.

| Attribute | Set by | Meaning |
|---|---|---|
| `data-herb-source="path:line:col"` | Herb | The element's open tag position, 1-based |
| A marker inside translated strings | Tensaku's I18n backend | Locale and key, stripped by the overlay |
| `data-tensaku-group` | The app | Widens the highlight and the edit target to this element |
| `data-tensaku-md="path:line:col-line:col"` | A Markdown producer | The block's Markdown source range, byte columns, end inclusive |
| `data-tensaku-permanent` | The app | The morph after a save leaves this element alone |

## Translation markers

In development, while a controller handles an HTML request, the I18n backend wraps each translated string in an invisible marker: U+2063, the locale and key encoded with zero-width characters, then U+2063. The overlay strips the markers when the page loads. The middleware strips them from `<script>`, `<style>` and non-HTML responses.

## Kiln

[Kiln](https://github.com/davafons/kiln)'s content layer adds `data-tensaku-md` in development when Tensaku is loaded, and Kiln's content directory is writable automatically. Kiln builds fail if any `data-herb-*` or `data-tensaku-*` attribute reaches the output. This site is built that way.
