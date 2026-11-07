# Tensaku

[Website and docs](https://tensaku.lostcoords.com) · [Source](https://github.com/lostcoords/tensaku)

Tensaku (添削, correcting a draft) lets you fix a running Rails app from the page itself, in
development. Click a piece of text and edit it in place, and Tensaku writes the change back to the ERB
template, the locale YAML or the Markdown source. Or leave a note on an element or an area of the page,
and your coding agent reads it with the exact file and line attached.

Tensaku is built on [Herb](https://github.com/marcoroth/herb) through
[ReActionView](https://github.com/marcoroth/reactionview), and only runs in development. Production
doesn't change: it keeps rendering with Erubi and never loads Tensaku, ReActionView or Herb.

Status: 0.0.1, unreleased. Requires Ruby 4.0+ and Rails 8.1 (8.2 isn't supported yet). Herb and
ReActionView are pinned to their current minor versions (0.11 and 0.6).

## Install

```ruby
# Gemfile
group :development do
  gem "tensaku"
end
```

```sh
bundle install
bin/rails generate tensaku:install
```

The generator checks the Gemfile group, writes `config/initializers/reactionview.rb`, installs the
Claude Code skill in `.claude/skills/tensaku/`, adds the MCP endpoint to `.mcp.json`, and makes sure
`tmp/` is ignored. It prints what it changed. No JavaScript setup is needed: the middleware injects one
prebuilt script, which works with importmap, jsbundling or no JavaScript at all.

## Use

Start the server and open a page. A small round button sits in the bottom right corner (drag it
anywhere). Click it for the toolbar, or press **Alt+Shift+T** to go straight to select mode.

- **Select**: hover to see where an element comes from (`h1  app/views/pages/about.html.erb:1`), click
  it for a menu:
  - **Copy reference**: `GET /about → app/views/pages/_hero.html.erb:4:3`, the text, the partial
    chain, the Stimulus controller, the Turbo Frame and the translation key.
  - **Add note**: write what should change. Select some text first to note just that text.
  - **Edit text** / **Edit attributes**, and **Edit the whole list** in a Markdown list.
  - **Open in editor**, through `RAILS_EDITOR` or `EDITOR`.
- **Arrow keys** in select mode move to the parent, a child or a sibling; Cmd+C copies the highlighted
  element's reference.
- **Drag** in select mode to note an area. The note collects every stamped element inside it.
- **Shift-click** elements in select mode to put several in one note.
- **Alt/Option-click** any text to edit it right away, in any mode.
- **Edit**: outlines every editable text on the page. A normal click edits.
- **Notes**: this page's notes or every page's, copy them as Markdown (detailed or one line each), edit,
  move, resolve or delete them, and keep a thread with the agent.
- **Pins** hides and shows the pins; the bin deletes every note on the page after a second click.
- **Edit history** lists this page's saves, with undo for each element's latest edit.
- **Settings**: copy format, background notifications, a compact corner button.

The editor shows the source, never the rendered text. In `Hello <%= user.name %>!` you edit `Hello ` and
`!`; the Ruby shows as a locked chip. Translations show `%{name}` interpolations as chips, and
"Other locales" lets you update the same key in every locale at once. Enter or leaving the editor
saves, Shift+Enter adds a line break in Markdown, Escape cancels. After a save, a toast offers Undo.

## What can be edited

| Source | How Tensaku finds it | Written to |
|---|---|---|
| Static text in ERB views, partials, layouts, ViewComponent sidecar templates, mailer templates | `data-herb-source="path:line:col"`, stamped by Herb's `SourceAttributionVisitor` | The template, only the bytes of that text |
| `alt`, `title`, `placeholder`, `aria-label`, button `value` | The same stamp | The attribute value, keeping its quotes |
| `t()` translations, in text and attributes | An invisible marker the I18n backend adds in development | The locale YAML, only the value's bytes |
| Markdown blocks (`p`, headings, `li`, `blockquote`) | `data-tensaku-md="path:line:col-line:col"` from a producer such as Kiln's content layer | The Markdown file, inside the block's range |

Everything else on the page (text from Ruby data like `@post.title`, output of `form_with` or custom
helpers, DOM built by JavaScript) can still get notes, placed through the nearest stamped element.

Every write is a splice: Tensaku re-reads the file, checks that the bytes it's about to replace are
still what the page was rendered from, and replaces exactly those bytes through a temp file and a
rename. YAML is never loaded and dumped, so comments, ordering and quoting stay. If the file changed
since the page rendered, the edit is refused and nothing is merged or guessed.

After a save, Tensaku clears Action View's template cache (and ViewComponent's, and reloads I18n),
updates every copy of the text on the page right away, then fetches the page again and morphs it in
with [idiomorph](https://github.com/bigskysoftware/idiomorph). Stimulus controllers stay connected,
no Turbo visit fires, and elements marked `data-turbo-permanent` or `data-tensaku-permanent` are left
alone. On a page reached by a POST (a form that rendered errors) Tensaku updates the text it knows and
asks you to reload.

Elements rendered in a loop share one stamp: the editor says "this edits all 3 copies".

## Notes for agents

Notes are JSON files in `tmp/tensaku/notes/`, one per note: local and ignored by git. Resolved notes are
deleted after three days. A note file that isn't valid JSON with an id and timestamps is skipped.

```json
{
  "id": "a7f3",
  "url": "/about",
  "comment": "tighten this, and the heading is wrong",
  "targets": [
    { "kind": "element", "file": "app/views/pages/_hero.html.erb", "range": "4:3-4:40", "tag": "h1", "text": "About me" }
  ],
  "status": "open",
  "reply": null
}
```

An agent gets them four ways:

- **Files**: read `tmp/tensaku/notes/*.json`.
- **MCP**: `http://localhost:3000/__tensaku/mcp` (Streamable HTTP). Tools: `list_notes`, `get_note`,
  `start_note`, `resolve_note`, `reply_to_note`, `ask_question`, `watch_notes` (waits for new notes) and `current_selection`. The
  generator adds it to `.mcp.json`.
- **Clipboard**: copy one note or all open notes as Markdown from the page, for any chat.
- **Claude Code skill**: `.claude/skills/tensaku/SKILL.md` explains how to find, act on and resolve notes.

A note is `open`, `working` (an agent called `start_note`), `question` (the agent asked something back;
the question shows on the page) or `resolved` (with a reply; the pin turns green so you can check the
change, then dismiss it). The page checks the notes every four seconds while it's visible, and a green
light on the toolbar shows that an agent called an MCP tool in the last 20 seconds.

## Producers and attributes

The overlay only reads attributes, so it doesn't care what rendered the page.

| Attribute | Set by | Meaning |
|---|---|---|
| `data-herb-source="path:line:col"` | Herb | Element's open tag position (1-based) |
| Marker inside translated strings | Tensaku's I18n backend | Locale and key. Stripped by the overlay. |
| `data-tensaku-group` | The app | Widen the highlight and the edit target to this element |
| `data-tensaku-md="path:line:col-line:col"` | A Markdown producer, development only | Block's Markdown source range (byte columns, end inclusive) |
| `data-tensaku-permanent` | The app | The morph after a save leaves this element alone (client-rendered islands) |
| `<meta name="tensaku" data-tensaku-request="GET">` | Tensaku | Request method, so the overlay knows whether it can fetch the page again |

[Kiln](https://github.com/davafons/kiln)'s content layer emits `data-tensaku-md` in development when
Tensaku is loaded, and Kiln's content directory is writable automatically. Kiln builds fail if any
`data-herb-*` or `data-tensaku-*` attribute reaches the output.

## Configuration

```ruby
# config/initializers/tensaku.rb
if defined?(Tensaku)
  Tensaku.configure do |config|
    config.writable_paths << "content"      # default: app/views app/components config/locales
    config.shortcut = "alt+shift+KeyT"      # modifiers and a KeyboardEvent#code
    config.prune_after = 7 * 24 * 60 * 60   # seconds before resolved notes are deleted
  end
end
```

Other gems can call `Tensaku.register_writable_path("their/dir")`.

## Safety

- Development only. The railtie, middleware and I18n markers check `Rails.env.development?`, so nothing
  loads in test or production even if the gem is in the wrong Gemfile group.
- Every endpoint answers requests from this machine only: a loopback peer address, no proxy header
  (`X-Forwarded-For`, `Forwarded` and similar) naming another client, a `Host` that is `localhost`, a
  `.localhost` name, a loopback IP or a name listed in the app's `config.hosts`, and no `Origin` from
  another site. The `Host` check stops DNS rebinding, where a site on another domain resolves its name
  to 127.0.0.1.
- Everything the overlay calls also needs a token embedded in the page. The token is kept in
  `tmp/tensaku/token`, so every Puma worker uses the same one and pages stay valid across a restart.
  Only successful pages (and 422 form errors) requested with a local `Host` get it; error pages and HTML
  fragments fetched by scripts don't.
- The MCP endpoint can't receive the token from an MCP client, so it relies on the checks above. It
  reads and updates notes; it never writes source files.
- Writes are limited to the writable paths, checked after resolving symlinks. Saves take a lock shared
  by every thread and server process, so two saves to one file can't overwrite each other.
- The injected script carries the page's Content Security Policy nonce when Rails generated one, and
  the overlay's styles use constructed stylesheets, so a nonce-based CSP doesn't block it.

## Limits

- Text from Ruby data, rich text (bold, links, splitting paragraphs), Phlex views and inline
  ViewComponent templates (`erb_template`) are out of scope. They get notes.
- Pluralized translations (`count:`) aren't marked, so they aren't edited in the page.
- Translation markers are part of the string while Ruby handles it, in development. A comparison like
  `t(".title") == "Welcome"` inside a controller action or view is false in development.
- Fragment caching in development (`bin/rails dev:cache`) keeps showing the old text from cached
  fragments. Tensaku warns when it's on.
- One person editing at a time. No undo history beyond one step: version control is the history.
- The server has to see the browser's connection as coming from this machine. Behind a tunnel (ngrok,
  cloudflared) or a reverse proxy that forwards other clients, and in Docker or a devcontainer where
  requests arrive from the container's gateway address, the overlay doesn't load and the endpoints
  answer 403.
- Translations get markers only from I18n backends that look keys up themselves: the Simple backend,
  backends built on it, and `I18n::Backend::Chain` over those. Strings from other backends aren't
  marked, so they aren't edited in the page.
- HTML responses are buffered to add the overlay. Responses from `ActionController::Live`, files sent
  from disk, downloads and compressed or non-UTF-8 bodies pass through unchanged and get no overlay.
- Herb's dev server patches template changes itself when it runs (ReActionView's `slots` option), and
  Tensaku then skips its own refetch for template edits.

## Development

```sh
bundle install
bun install          # only to change the overlay
bin/test             # unit and browser tests (Cuprite, needs Chrome)
bin/lint             # RuboCop, house rules, TypeScript, compiled overlay up to date
bun run build        # app/javascript/tensaku/*.ts -> app/assets/tensaku.js (committed)
```

The documentation site is a Rails app in `docs/`, rendered to static files by Kiln and styled with
lostcoords-ui. Tensaku runs on it in development, so it's also where Tensaku is tried on a real site:

```sh
cd docs
bundle install
bin/rails tailwindcss:build
bin/rails server                          # edit the docs from the page
RAILS_ENV=production bin/rails kiln:build # static site in docs/dist
```

With [Parcela](https://parcela.run), `parcela up --detach` runs the docs server and the Tailwind watcher at
https://tensaku.localhost.

CI builds the docs with `kiln:build` on every push.

The test suite runs `test/dummy` in the development environment, since that's the only place Tensaku
switches on. Browser tests write to the dummy app's files and restore them afterwards.

## License

MIT
