# Safety and limits

## Safety

- **Development only.** The railtie, middleware and I18n markers check `Rails.env.development?`, so nothing loads in test or production, even if the gem is in the wrong Gemfile group.
- **Loopback only.** Every endpoint answers loopback addresses only. Everything the overlay calls needs a per-boot token embedded in the page.
- **MCP.** An MCP client can't receive the page's token, so the MCP endpoint also refuses requests with a foreign `Origin` or a non-local `Host`. It reads and updates notes and never writes source files.
- **Writable paths.** Writes are limited to the writable paths, checked after resolving symlinks.

## Limits

- Text from Ruby data, rich text (bold, links, splitting paragraphs), Phlex views and inline ViewComponent templates (`erb_template`) can't be edited. They get notes.
- Pluralized translations (`count:`) aren't marked, so they can't be edited in the page.
- Translation markers are part of the string while Ruby handles it, in development. A comparison like `t(".title") == "Welcome"` is false in development.
- Fragment caching in development (`bin/rails dev:cache`) keeps showing the old text from cached fragments. Tensaku warns when it's on.
- One person edits at a time. Undo goes back one step; version control is the history.
- The morph after a save removes attributes that client-side code added to an element. Mark those elements `data-tensaku-permanent`.
