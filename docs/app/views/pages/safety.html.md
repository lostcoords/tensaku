# Safety and limits

## Safety

- **Development only.** The railtie, middleware and I18n markers check `Rails.env.development?`, so nothing loads in test or production, even if the gem is in the wrong Gemfile group.
- **This machine only.** Every endpoint needs a loopback peer address, no proxy header naming another client, a `Host` that is `localhost`, a `.localhost` name, a loopback IP or a name in the app's `config.hosts`, and no `Origin` from another site. The `Host` check stops DNS rebinding, where a site on another domain resolves its name to 127.0.0.1.
- **Token.** Everything the overlay calls needs a token embedded in the page. The token lives in `tmp/tensaku/token`, so every Puma worker shares it and pages stay valid across a restart. Only successful pages and 422 form errors requested with a local `Host` get it. Error pages and HTML fragments that scripts fetch don't.
- **MCP.** An MCP client can't receive the page's token, so the MCP endpoint relies on the checks above. It reads and updates notes and never writes source files.
- **Writable paths.** Writes are limited to the writable paths, checked after resolving symlinks. Saves take a lock shared by every thread and server process, so two saves to one file can't overwrite each other.
- **Content Security Policy.** The injected script carries the page's CSP nonce, and the overlay's styles use constructed stylesheets, so a nonce-based policy doesn't block it.

## Limits

- Text from Ruby data, rich text (bold, links, splitting paragraphs), Phlex views and inline ViewComponent templates (`erb_template`) can't be edited. They get notes.
- Pluralized translations (`count:`) aren't marked, so they can't be edited in the page.
- Translation markers are part of the string while Ruby handles it, in development. A comparison like `t(".title") == "Welcome"` is false in development.
- Fragment caching in development (`bin/rails dev:cache`) keeps showing the old text from cached fragments. Tensaku warns when it's on.
- One person edits at a time. Undo goes back one step. Version control is the history.
- The server has to see the browser's connection as coming from this machine. Behind a tunnel such as ngrok or cloudflared, behind a reverse proxy that forwards other clients, and in Docker or a devcontainer, the overlay doesn't load and the endpoints answer 403.
- Only I18n backends that look keys up themselves get translation markers: the Simple backend, backends built on it, and `I18n::Backend::Chain` over those. Strings from other backends can't be edited in the page.
- Tensaku buffers HTML responses to add the overlay. Streamed responses (`ActionController::Live`), files sent from disk, and compressed or non-UTF-8 bodies pass through unchanged and get no overlay.
- When Herb's dev server runs (ReActionView's `slots` option), it patches template changes itself, and Tensaku skips its own refetch after a template edit.
- The morph after a save removes attributes that client-side code added to an element. Mark those elements `data-tensaku-permanent`.
