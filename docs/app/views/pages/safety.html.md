# Safety and limits

Tensaku is a development tool that writes to your source files. This page says what keeps it on your machine and what it can't do.

After reading this page, you will know:

- What Tensaku can reach, and where it runs.
- What can't be edited.
- Where it doesn't work, and how it can change rendering in development.

## Safety

Tensaku loads only when `Rails.env.development?` is true, so nothing changes in test or production, even if the gem is in the wrong Gemfile group. Its endpoints only answer requests from this machine, and it only writes inside the writable paths. The MCP server, `tensaku mcp`, runs as a child process of your agent over stdin and stdout, not on the network. It reads and updates notes and never writes source files. Notes are in a SQLite database in your user data folder, in a folder only your user can open (on macOS and Linux), and are never sent anywhere. A nonce-based Content Security Policy doesn't block the overlay.

## Limits

### What can't be edited

- Text from Ruby data, rich text (bold, links, splitting paragraphs), Phlex views and inline ViewComponent templates (`erb_template`). They get notes.
- Pluralized translations (`count:`), which aren't marked.
- Strings from I18n backends that don't look keys up themselves. Translation markers need the Simple backend, a backend built on it, or `I18n::Backend::Chain` over those.

### Where it doesn't load

- **Tunnels, proxies and containers.** The server has to see the browser's connection as coming from this machine. Behind a tunnel such as ngrok or cloudflared, behind a reverse proxy that forwards other clients, and in Docker or a devcontainer, the overlay doesn't load and the endpoints answer 403.
- **Some responses.** Tensaku buffers HTML responses to add the overlay. Streamed responses (`ActionController::Live`), files sent from disk, and compressed or non-UTF-8 bodies pass through unchanged and get no overlay.

### How it behaves in development

- **Translation markers** are part of the string while Ruby handles it. A comparison like `t(".title") == "Welcome"` is false in development.
- **Fragment caching** (`bin/rails dev:cache`) keeps showing the old text from cached fragments. Tensaku warns when it's on.
- **Herb's dev server** (ReActionView's `slots` option) patches template changes itself, and Tensaku skips its own refetch after a template edit.
- **The morph after a save** removes attributes that client-side code added to an element. Mark those elements `data-tensaku-permanent`.
- **Undo** covers the saves made in the browser tab, and one person edits at a time. Version control is the longer history.

### Tag helpers

Tag helpers such as `link_to` and `tag.div` render as they do in production and have no source stamp of their own, so a note on their output points at the nearest stamped ancestor.

Setting `config.engine.parser_options = { action_view_helpers: true }` in `config/initializers/reactionview.rb` adds those stamps, but Herb 0.11.2 then drops attributes passed with a double splat, such as `tag.div(**attrs)` or `content_tag(:div, "x", **attrs)`, in development. The element still renders without them and nothing reports it, so classes and Stimulus controllers can go missing. This is [Herb issue #2737](https://github.com/marcoroth/herb/issues/2737).
