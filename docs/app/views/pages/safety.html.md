# Safety and limits

## Safety

- **Development only.** The railtie, middleware and I18n markers check `Rails.env.development?`, so nothing loads in test or production, even if the gem is in the wrong Gemfile group.
- **This machine only.** Every endpoint needs a loopback peer address, no proxy header naming another client, a `Host` that is `localhost`, a `.localhost` name, a loopback IP or a name in the app's `config.hosts`, and no `Origin` from another site. The `Host` check stops DNS rebinding.
- **Token.** Everything the overlay calls needs a token embedded in the page, kept in `tmp/tensaku/token` so every Puma worker shares it. Only successful pages (and 422 form errors) requested with a local `Host` get it; error pages and HTML fragments fetched by scripts don't.
- **MCP.** An MCP client can't receive the page's token, so the MCP endpoint relies on the checks above. It reads and updates notes and never writes source files.
- **Writable paths.** Writes are limited to the writable paths, checked after resolving symlinks. Saves take a lock shared by every thread and server process.
- **Content Security Policy.** The injected script carries the page's CSP nonce, and the overlay's styles use constructed stylesheets.

## Limits

- Text from Ruby data, rich text (bold, links, splitting paragraphs), Phlex views and inline ViewComponent templates (`erb_template`) can't be edited. They get notes.
- Pluralized translations (`count:`) aren't marked, so they can't be edited in the page.
- Translation markers are part of the string while Ruby handles it, in development. A comparison like `t(".title") == "Welcome"` is false in development.
- Fragment caching in development (`bin/rails dev:cache`) keeps showing the old text from cached fragments. Tensaku warns when it's on.
- One person edits at a time. Undo goes back one step; version control is the history.
- The morph after a save removes attributes that client-side code added to an element. Mark those elements `data-tensaku-permanent`.
