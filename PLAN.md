# Tensaku — plan

Tensaku (添削, correcting a draft) lets you fix a running Rails app from the page itself, in development.
Click a piece of text and edit it in place, and Tensaku writes the change back to the template, the
locale file or the Markdown source. Or leave a note on an element or an area of the page, and your coding
agent reads it with the exact file and line attached, instead of a screenshot and "change this".

Status (2026-11-08): phases 0 to 6 are implemented and tested, unreleased. The repo is public at
github.com/lostcoords/tensaku, with docs at tensaku.lostcoords.com. The RubyGems name and the 0.1 release
wait for approval. Each phase below keeps what building it taught.
Prior art: [RESEARCH.md](RESEARCH.md) (state of Herb, Rails, threads) and [REFERENCES.md](REFERENCES.md)
(related projects).

## Why

Changing text today means finding the file by hand, or telling an agent "change this" with a
screenshot that links to nothing. Both are slow, and the agent has to guess where the text comes from.

Existing tools each solve part of the problem:

| Source | What it is | Problem |
|---|---|---|
| [Herb](https://github.com/marcoroth/herb) 0.11 / [ReActionView](https://github.com/marcoroth/reactionview) 0.6 | HTML-aware ERB parser and engine, merged into Rails for 8.2. `SourceAttributionVisitor` stamps every element with `data-herb-source="file:line:col"`. ReActionView adds dev tools (template outlines, "Open in Editor") and a dev server that patches the open page when a template changes. | File → browser only. Nothing writes back to files, no translation keys, no notes. |
| [agentation-rails](https://github.com/hellobrightline/agentation-rails) | Dev toolbar: click, drag or select text, write a comment, copy Markdown. | File-level at best (CSS selectors, partial names). Notes live in localStorage and reach the agent only by pasting. No editing. PolyForm Shield license, so it can't be forked. |
| Agentation, Pinagent, Pinpoint, Vibe Annotations, UI Annotator MCP, CommentKit | Annotation tools for coding agents, several with MCP. | They find source through React internals or build-time attributes for JS frameworks (Agentation added `file:line` in 2.3.0). On a Rails page they only see selectors. None edits text. |
| [Tidewave](https://tidewave.ai) | Point-and-click prompting in the browser, to Claude Code, Codex, OpenCode or an ACP agent. The `tidewave` gem is a free MCP server (eval, SQL, docs). | The browser toolbar is paid ($8 a month). No in-page editing. |
| rails-i18n-onair, i18n_proofreading, i18n_viz, i18n-edit | Edit or suggest translations in the page. | Translations only. Mostly old. Some store translations in a database instead of YAML. |

Tensaku is the missing layer on top of Herb: write-back for template text, attributes, translations and
Markdown, plus notes with exact positions that an agent can read.

## Core decisions

### 1. Built on Herb, through ReActionView, in development only

- Rails 8.1+. Rails 8.1 has no Herb template handler, so Tensaku depends on
  [ReActionView](https://github.com/marcoroth/reactionview), which provides one and lets other gems add
  Herb visitors (`config.engine.visitors.use(...)`).
- **Nothing changes in production.** Tensaku and ReActionView go in the `development` group, so
  production (and static builds, which run in production) keep rendering with Erubi. No backports, no
  patches to Rails.
- Development renders with Herb and production with Erubi. Rails states that valid templates render
  the same output with both, and ReActionView's validation overlay shows invalid HTML in development,
  where it would cause a difference.
- In development, Tensaku turns on ReActionView's ERB interception and registers Herb's
  `SourceAttributionVisitor`. Tensaku never parses or transforms templates for rendering itself.
- ReActionView also brings Herb's dev tools ("Open in Editor", outlines) and, with slots on, the dev
  server that patches the page live.
- Rails 8.2 (unreleased; latest is 8.1.4.1) has Herb built in. Once it ships, revisit whether
  ReActionView is still needed or Tensaku can register its visitor on Rails' own handler.
- Runtime dependencies: `railties`, `actionpack`, `herb`, `reactionview`.

### 2. Development only, local only

- The gem belongs in the `development` group. The middleware, routes and overlay also check
  `Rails.env.development?`, so nothing loads in test or production even if the gem is in the wrong group.
- Write endpoints accept requests from this machine only (loopback peer, no forwarded client, a local
  `Host`, no foreign `Origin`), and need a token that is embedded in the page.
- Writes are limited to an allow-list: `app/views`, `app/components`, `config/locales`, plus paths the
  app adds to `writable_paths` or other gems register with `Tensaku.register_writable_path`.
- Kiln fails a build if any `data-herb-*`, `data-tensaku-*` or `data-md-source` attribute reaches the
  output.

### 3. The editor edits the source, never the rendered text

- Text nodes aren't stamped. Tensaku finds them from the parent element's stamp: the server re-parses
  the file with Herb, finds the element at that position, and returns its children as source pieces.
- Mixed text like `Hello <%= user.name %>!` is one text node in the browser ("Hello David!") and three
  pieces in the file. The editor shows `Hello [user.name]!`, with the Ruby as a locked chip, and you edit
  the static parts. The same applies to translation interpolation (`Hello [%{name}]`), HTML entities and
  inline Markdown.
- Child elements show as they look on the page rather than as code: `<br>` breaks the line, an element's
  text keeps its style, dimmed, and opens that element's editor on a click, and an element without text
  is a small mark. Elements positioned out of the flow aren't shown, and whitespace between elements
  isn't a field.
- An element Herb can't stamp (output of `form_with` or a custom helper, DOM built by JavaScript) gets
  notes through its nearest stamped ancestor, but its text can't be edited.
- Elements rendered in a loop share one stamp (the line they were written at), like a partial rendered
  several times. The editor says "this edits all N copies" before saving.
- Translations aren't stamped by Herb (`t()` output is built in Ruby). In development, Tensaku's I18n
  backend appends an invisible marker with the key and locale to each translated string, and the overlay
  strips the markers on load and remembers which key produced each text or attribute. This is the
  [i18n_proofreading](https://github.com/yshmarov/i18n_proofreading) technique. It works inside
  attributes, which a wrapper element can't. Never on `number.*`/`date.*` keys or keyless `default:`
  values, and only in HTML responses.

### 4. Edits are surgical splices, never re-serialization

- Template text and attributes: re-parse with Herb, check that the bytes at the target range still
  equal what the page was rendered from, escape the new text for its context (HTML text or attribute
  value), replace exactly those bytes, write atomically.
- YAML: never load-and-dump, which drops comments, ordering and quoting. Psych's parse tree gives each
  scalar's start and end position, so Tensaku replaces only the value's bytes and keeps its quoting
  style.
- Markdown: a producer reports block source ranges (decision 8), and Tensaku replaces text inside them.
- A mismatch (the file changed since the page rendered) is refused with a clear message. Nothing is
  merged or guessed.
- After a write, the server clears Action View's template cache and reloads I18n, so the next request
  can't race Rails' file watcher. Tensaku warns when fragment caching is on in development
  (`rails dev:cache`), because cached fragments would keep showing the old text.
- The save reply carries the changed lines (`FileWrite.diff`, from the file's bytes before and after the
  write), and the toast shows them, so a save visibly reaches the file.
- Undo: an undo and a redo stack of the text saves made in the tab (same stale-file check), kept
  across reloads. Version control is the longer history.

### 5. Updating the page after a save

No single strategy works for every setup, so Tensaku layers them:

1. **Right away:** update every node on the page from the same source (repeated partials, the same
   translation key), when the rendered text equals the source text.
2. **Then check against the server:** fetch the current URL again and morph the page with
   [idiomorph](https://github.com/bigskysoftware/idiomorph), bundled in Tensaku's JavaScript. It works
   the same with or without Turbo, doesn't fire Turbo visit events, keeps scroll and focus, and respects
   `data-turbo-permanent` and `data-tensaku-permanent` (for client-rendered islands).
3. **Pages reached by a POST** (a form that rendered errors) can't be fetched again. The middleware marks
   the request method on the page. On those pages Tensaku keeps step 1 and shows "reload to check".
4. **Herb live patching:** when ReActionView's dev server is already running, it replaces step 2 for
   template text.

| Setup | Expected behavior |
|---|---|
| Hotwire, Turbo Drive | Step 1, then morph. Stimulus controllers stay connected. |
| Turbo Frames | Morph. Lazy frames load again. |
| No Turbo, htmx, plain HTML | Step 1, then morph. |
| React or Vue islands | Step 1. Morph skips elements marked permanent. |

### 6. Two kinds of marks: edits and notes

Like Japanese proofreading, which marks definite corrections in red (赤字, *akaji*) and questions for
the author in pencil (鉛筆, *enpitsu*):

- **Edit:** you change the text yourself, and the file changes. Only for text with a known, writable
  source.
- **Note:** you describe what should change ("too much spacing", "rename this section"), and an agent
  does it. Works on anything on the page, including text that comes from Ruby data.

### 7. Notes are local files the agent can read

- One JSON file per note in `tmp/tensaku/notes/`: local, ignored by git. Notes
  are short-lived instructions, not project history.
- A note holds the URL, the comment, every target's file, range, kind and text, the rectangle and
  viewport for area notes, a status and a thread of messages. No screenshots: the agent can take its own with a browser tool.
- Lifecycle: `open` → `working` (an agent picked it up) → `resolved` with a short reply ("changed the
  heading in `_hero.html.erb:4`"), or `declined` with the reason. The agent can also set `question` when
  the note is unclear, and the pin shows the question on the page. Resolved pins turn green so you can check the change, then you
  clear them from the panel or they're deleted after `config.prune_after`.
- Four ways for agents to get notes, all in 0.1:
  - **Files:** agents read `tmp/tensaku/notes/*.json` directly.
  - **MCP server** `tensaku mcp`, which the agent starts over stdio: `list_notes`, `get_note`, `start_note`, `resolve_note`,
    `decline_note`, `ask_question`, `reply_to_note`, `watch_notes` (waits for notes you send, so an
    agent can work through them as you send them), `current_selection`. Modeled on Agentation's MCP
    (see RESEARCH.md).
  - **Copy to clipboard:** one note or all open notes as Markdown, for any chat.
  - **Skill** shipped with the gem, for Claude Code in `.claude/skills` and for other agents in
    `.agents/skills`: how to find, act on and resolve notes.
- Sending: saving a note sends it. An agent waiting in `watch_notes` gets it; any other agent gets it
  the next time you ask it to look (decisions log, "Agents connect over stdio").

```json
{
  "id": "a7f3",
  "url": "/about",
  "comment": "tighten this, and the heading is wrong",
  "targets": [
    { "kind": "text", "file": "app/views/pages/_hero.html.erb", "range": "4:3-4:40", "text": "About me" },
    { "kind": "element", "file": "app/views/pages/_hero.html.erb", "range": "6:1-9:7", "tag": "p.intro" }
  ],
  "rect": { "x": 120, "y": 340, "width": 600, "height": 180 },
  "viewport": "1440x900",
  "status": "open",
  "thread": [],
  "created_at": "2026-11-07T18:00:00.000000Z",
  "updated_at": "2026-11-07T18:00:00.000000Z"
}
```

### 8. A small documented attribute format

Producers (Herb, Tensaku, Kiln's content layer, other gems) mark the HTML. The overlay only reads
attributes, so it doesn't care what rendered the page. Tensaku handles Markdown only through producers:
it doesn't render Markdown itself.

| Attribute | Set by | Meaning |
|---|---|---|
| `data-herb-source="path:line:col"` | Herb | Element's open tag position |
| Marker inside translated strings | Tensaku's I18n backend, development only | Text came from this key and locale. Stripped by the overlay. |
| `data-tensaku-group` | The app | Widen the highlight and the edit target to this element, for cases the automatic mapping gets wrong |
| `data-md-source="path:line:col-line:col"` | Kiln (or another Markdown producer), development only | Block's Markdown source range |
| `data-tensaku-permanent` | The app | The morph after a save leaves this element alone |
| `data-tensaku-request="GET"` (meta tag) | Tensaku | Request method, so the overlay knows whether it can fetch the page again |

### 9. No Node for apps

- One prebuilt JavaScript file with idiomorph bundled, injected by the middleware before `</body>`.
  Works with importmap, jsbundling or no JavaScript setup at all.
- The overlay is written in TypeScript and compiled before release. The compiled file is committed and
  shipped in the gem, so only Tensaku contributors need a JS toolchain (esbuild or bun).

## Features

| Feature | Phase | Notes |
|---|---|---|
| Copy reference | 1 | Click an element and copy `GET /about → app/views/pages/_hero.html.erb:4:3`, the text, the partial chain and the nearest Stimulus controller and Turbo Frame. |
| Notes on an element | 2 | Click, write a comment, save. |
| Notes on an area | 2 | Drag a rectangle. The note collects every stamped element the rectangle overlaps. |
| Notes on the page | 2 | Pins, and a panel with the notes for the current URL. Resolved pins turn green. |
| Notes for agents | 3 | Files, `tensaku mcp` (stdio), copy to clipboard, skill. |
| Send to agent | 3 | Saving a note sends it; an agent waiting in `watch_notes` picks it up. |
| Pause animations | 2 | Toolbar button: pauses CSS animations, transitions, Web Animations and media. |
| Edit template text | 4 | Alt/Option-click an element for its menu, where Edit text comes first, or turn on edit mode from the toolbar to see every editable text highlighted and edit with a normal click. Save on Enter or blur. Ruby shows as locked chips. |
| Edit attribute text | 4 | `alt`, `title`, `placeholder`, `aria-label`, button `value`: a small form per element. |
| Undo | 4 | Undo and redo from the toast, the keyboard and the edit history, for the tab's text saves. |
| Page update after saving | 4 | Decision 5. |
| Edit translations | 5 | Edits the page's locale. A toggle shows the same key in the other locales, to update them together or see they're out of date. |
| Edit Markdown | 6 | Through `data-md-source` from a producer such as Kiln's content layer. Paragraphs, headings, list items, quotes and whole lists; code, tables and rules get notes only. |
| Corner button and shortcut | 1 | A small draggable button in a corner with the open-note count, plus a keyboard shortcut to toggle the overlay. Pins show whenever notes exist. |
| ViewComponent templates | 1 | Sidecar `.html.erb` templates compile through Herb, so references, notes and edits work. Inline templates (`erb_template` in Ruby) don't. |
| Mailer previews | 4 | Edit HTML email templates from `/rails/mailers` previews. Needs a test that previews render through Herb. |
| Install generator | 3 | `bin/rails generate tensaku:install`: Gemfile group check, skill in `.claude/skills/tensaku/` and `.agents/skills/tensaku/`, `tensaku mcp` in `.mcp.json` and in Codex, Cursor, Gemini CLI and OpenCode configs (`--agents`, or those already in the project), `tmp/` ignored. Prints what it changed. |
| Open in editor | 4 | `GET /editor` builds the link through Rails' `ActiveSupport::Editor` and `RAILS_EDITOR`. |

### Out of scope

- Editing text that comes from Ruby data (`@post.title`). It gets notes and a reference to the ERB
  expression, not editing.
- Rich text editing (bold, links, splitting paragraphs). One text node at a time.
- Rendering Markdown. Producers like Kiln do that.
- Phlex views (Ruby, not ERB, so Herb can't stamp them).
- Anything in production or test.
- Any environment other than development. No staging editor, no hosted service, no accounts.
- Several people editing at the same time.

## Shape

```
lib/tensaku.rb                  entry point, configuration
lib/tensaku/railtie.rb          dev-only: ReActionView interception, visitor, middleware
lib/generators/tensaku/         install generator
lib/tensaku/middleware.rb       injects the overlay and request meta, routes to the endpoints
lib/tensaku/endpoints.rb        JSON endpoints the overlay calls
lib/tensaku/guard.rb            request checks, boot token, path allow-list
lib/tensaku/file_write.rb       byte splices, atomic writes, the shared write lock
lib/tensaku/source/template.rb  text and attribute pieces from an element stamp, splice
lib/tensaku/source/html_text.rb escaping and entity handling for template text
lib/tensaku/source/locale.rb    find a YAML scalar by key, splice its value
lib/tensaku/source/markdown.rb  splice inside a producer's block range
lib/tensaku/i18n.rb             I18n backend that adds key markers in development
lib/tensaku/caches.rb           clears template caches and reloads I18n after a write
lib/tensaku/notes.rb            notes, agents, selections: list, claim, resolve, archive
lib/tensaku/store.rb            the SQLite database in the user data folder, schema
lib/tensaku/doorbell.rb         Unix sockets that wake waiting readers after a write
lib/tensaku/repo.rb             the commit and origin of an app, read from .git
lib/tensaku/mcp.rb              MCP server over stdio (`tensaku mcp`), no Rails
lib/tensaku/cli.rb              the `tensaku` command
skills/tensaku/SKILL.md         Claude Code skill
app/javascript/tensaku/         overlay source (TypeScript)
app/assets/tensaku.js           compiled overlay, committed
test/dummy/                     Rails 8.1 app used by the test suite
docs/                           documentation site, a separate Rails app built with Kiln
```

## Work log

Features first. Tests cover the splicing (where a bug corrupts files) and the main flows, without
chasing coverage. Phases 0 to 6 are done; their findings stay as the record of why things work the way
they do.

### Phase 0 — workspace

Findings (2026-11-07):

- `gem build` packages the right files.
- Spike before building on it: ReActionView 0.6.1 plus `SourceAttributionVisitor` stamps layouts,
  views, partials rendered in a loop, `link_to` (through `action_view_helpers`, which the visitor turns
  on by itself) and ViewComponent sidecar templates on Rails 8.1.4.1. Mailer previews render through
  Herb with no extra work.
- Herb positions are 1-based lines and 0-based character columns (stamps add 1); token ranges are byte
  offsets. Psych columns are characters too. Kiln's `data-md-source` columns are bytes. Every splice
  converts to byte offsets and has a multibyte test.
- The test suite runs the dummy app in the development environment, since that is where Tensaku is on.
  Tests wrapped in the executor hold the load interlock that the view reloader needs after a write, so
  the dummy app sets `active_support.executor_around_test_case = false`.
- Tensaku requires ReActionView and Herb only in development, and the rest of the gem autoloads.
  A test boots the dummy in production and test with Tensaku required, and checks that Erubi renders
  and nothing from Tensaku, ReActionView or Herb is loaded or emitted.
- With `action_view_helpers: true`, every dummy page renders byte for byte the same under Herb in
  development and Erubi in production once stamps, markers and the overlay are removed (the only other
  difference is ReActionView's own importmap pin). Checked by a test.
- House rules from Kiln run here too; PLAN.md, RESEARCH.md, REFERENCES.md and ART_STYLE.md are exempt
  from the dash rule.

### Phase 1 — references

Findings: the overlay lives in a shadow root on an element attached to `<html>`, outside `<body>`, so
Turbo body swaps and the morph never touch it. The default shortcut is Alt+Shift+T
(changed per browser in the settings panel). ReActionView's debug mode (Herb dev tools) wraps ERB output in
`display: contents` spans; the overlay treats them as part of the parent element's text.

### Phase 2 — notes

Findings: block elements span the whole line, so an area note measures each element's content extent
(a range over its children) and keeps elements that are at least half inside the rectangle, outermost
first. Notes without targets show in the panel only, with no pin. Text-selection notes (kind `text`)
come from selecting text before clicking in select mode. Answering a question appends the answer to
the comment and sets the note back to open.

### Phase 3 — notes for agents

Findings: the first MCP server was an HTTP endpoint on the dev server. It needed the server running
before the agent, a port in every agent's config, and a loopback-only check in place of a token. It
was replaced by `tensaku mcp` over stdio (decisions log, "Agents connect over stdio").

### Phase 4 — editing templates

Findings (2026-11-07):

- Spike results, as browser tests: on the Hotwire page the morph keeps the Stimulus controller
  connected (no disconnect) and fires no Turbo visit; Turbo Frame content morphs and the lazy frame
  loads again (the overlay calls `reload()` on lazy frames that come back as placeholders); the page
  without Turbo updates the same way; a page reached by a POST updates in place and says "reload to
  check". The morph also brings in changes made to the file by someone else.
- The morph removes attributes that client code added and the server doesn't render (a Stimulus
  controller setting `data-*` on its element). Mark such elements `data-tensaku-permanent`.
- The stale-file check on the server compares the bytes at the range with what the editor loaded. The
  editor loads the source when it opens, which can be after the file changed, so the overlay also
  checks that the static source text still appears in the rendered element before it lets you edit.
  Without that, an outside change made after the page rendered was silently overwritten (found by a
  browser test).
- Herb live patching is detected through the `herb-dev-server-port` meta tag, and then the refetch is
  skipped for template edits. Not exercised by the tests (it needs ReActionView's `slots`).
- `link_to` and other helper output is stamped but its text isn't editable (the open tag is ERB).

### Phase 5 — translations

Findings: markers are invisible: U+2063, then "locale:key" in base 4 with four zero-width characters,
then U+2063. They're added only while a controller handles an HTML request, never to `number.*`,
`date.*`, `time.*` and similar keys, never to a value from `default:`, and never to pluralized lookups
(so `count:` translations aren't edited in the page). The middleware strips them from non-HTML
responses and from `<script>` and `<style>`. A Ruby comparison with a translated string sees the
marker in development. Every YAML write is verified by loading the result before the file is
replaced; a plain scalar that would change meaning is written double-quoted; `%{...}` placeholders
must stay the same.

### Phase 6 — Markdown

Findings: Kiln's headings contain no anchor link (`<h2 id="slug">Text</h2>`), so nothing needs
ignoring. `data-md-source` columns are commonmarker's byte columns, end inclusive. Heading hashes,
list markers and quote markers are locked; the rest of the block is edited as Markdown source. `p`,
headings, `li` and `blockquote` are editable, and a whole list as source; tables and code only get
notes. The dummy app tests with a stand-in producer; the docs site runs it against Kiln.

### Phase 7 — adopt

The docs site (`docs/`, added 2026-11-07) is the first real site Tensaku runs on.

Findings (2026-11-07): the docs app is Rails 8.1 with lostcoords-ui 0.8.2 for the layout and Kiln's
content layer for the pages, which are `.html.md` views. In development Herb stamps the layout and
Kiln marks every Markdown block, and the Alt-click, edit, Enter flow writes the paragraph back with
only that line changed. `RAILS_ENV=production bin/rails kiln:build` writes `docs/dist/` with no Herb
or Tensaku markup. It uses Kiln 0.1.1 from RubyGems, and CI builds
the docs on every push. Parcela runs only the dev server and the Tailwind watcher: Kiln has no
watcher, and a production build next to a booting dev server can leave it serving the production
asset manifest, so builds run on demand or in CI. A controller that inherits `ActionController::Base`
directly only looks for its own layout, which looked like missing stamps at first.

From using it on the docs: ReActionView 0.6.1 turns its debug mode on by default in development, and
its dev tools then wait for Herb's dev server (which only runs with `slots`) and warn that nothing
listens on port 8592. Tensaku doesn't need debug mode, so the generator now writes
`debug_mode = false`. A note on a Kiln paragraph also pointed at the stamped `<article>` around it,
and its pin sat on the article; a Markdown block inside the nearest stamped element now replaces it.

The landing page (2026-11-07) has a live demo: the real `tensaku.js` against an in-browser stand-in
for the endpoints, which splices an in-memory copy of a demo partial by the offsets Tensaku itself
reported (`script/demo_data.rb` records them in development). The page ships the stamps renamed,
because Kiln refuses `data-herb-*` in its output. Writing the demo found an overlay assumption: the
page refetch must not contain the overlay element, or the parser moves it into `<body>` and the morph
adds a second one.

- [ ] Claim the `tensaku` name on RubyGems (ask before `gem push`).
- [x] Move `docs/` to Kiln 0.1.3, which writes `data-md-source` (Markdown editing on the docs site
      needs it).
- [ ] davafons.com on Rails + Kiln.
- [ ] lostcoords-ui docs.
- [ ] wariwari (server-rendered, no Kiln).
- [ ] Release 0.1.

### After 0.1

- [ ] When Rails 8.2 ships: decide whether ReActionView stays a dependency or Tensaku registers its
      visitor on Rails' own Herb handler.
- [ ] Talk to the Herb maintainers about upstreaming what belongs there (for example text-node source
      positions or write-back).

## Risks

- **Herb in development, Erubi in production.** Valid templates render the same with both, but an
  invalid one (an unclosed tag) can differ. ReActionView's validation overlay flags those in development.
- **ReActionView is pre-1.0** and does more than Tensaku needs (reactive templates, debug mode). Its
  debug mode wraps ERB output in `display: contents` spans in development, which changes the DOM a
  little.
- **`action_view_helpers: true`**, which source attribution recommends, makes Herb write helpers like
  `link_to` out as markup at compile time. Test that pages render the same before turning it on, or
  accept fewer stamps without it.
- **Elements without stamps** (custom helpers, JavaScript-built DOM) can only get notes, through the
  nearest stamped ancestor.
- **Morphing** can overwrite client-rendered DOM that isn't marked permanent.
- **Herb's own dev tools** may grow in this direction. See [RESEARCH.md](RESEARCH.md).

## Decisions log

- **Name:** `tensaku` (添削). Free on RubyGems and npm, no conflicting project.
- **Note cards (changed 2026-11-09):** no message box and no copy button on a card. A note is already a message to the agent, so a change of mind is an edit, and only a question takes an answer. Copying stays in the panel, for chats without MCP. Card actions are unoutlined icons with tooltips. Resolved notes have a section in the panel with **Clear resolved**; they are not hidden, because the green pin and the reply are how you check the work.
- **Agent toasts (added 2026-11-09):** one at a time, at most three at once, and a backlog of more than three becomes one toast that counts the changes. An agent that resolves everything at the end should still not fill the screen.
- **MCP replies (changed 2026-11-09):** text only, no `structuredContent`, and one line for a state change. Sending a note twice cost tokens on every call. `checked_at` moved into the text of `watch_notes`. The skill and tool descriptions tell the agent to resolve each note as soon as it's done.
- **One record of the conversation (changed 2026-11-09):** a note's `thread` is everything the agent and you said. The separate `reply` field was a copy of the agent's last message, and editing a note cleared it while the thread stayed visible. Starting a note shows on its pin only, with no toast, because most of the toast noise from a long run was "started".
- **Notes and changing code (added 2026-11-09, storage replaced by "Notes in SQLite" on 2026-11-13):** notes stay in `tmp/tensaku/notes`, per checkout, rather than in a shared location outside the project. Rails already ignores `tmp/`, pulls and rebases do not touch it, and a note is about the code in its own checkout. `notes_path` was removed on 2026-11-13, so a process without Rails always finds them. Pins find elements again by tag and text in the same file when lines move. The recorded `range` is not rewritten, because that would make `watch_notes` report every note as changed.
- **Generator (changed 2026-11-09):** optional, for connecting an agent only. The railtie sets everything needed to edit and leave notes.
- **Logo (added 2026-11-09):** a hanamaru, the flower a teacher draws on good work, in one red stroke. Chosen over a T in a flower and a T in a circle. Three strokes plus a T was ruled out because it reads as 汀, a different kanji. `hanamaru-small.svg` is the thicker cut for small sizes, in `docs/app/assets/images/`, and `logo()` in `icons.ts` holds a copy for the overlay.
- **Separate gem**, not part of Kiln. Kiln doesn't carry Herb, and server-rendered apps like wariwari use
  Tensaku without a static exporter.
- **Rails:** 8.1+, Herb through ReActionView. Development only: production keeps Erubi, with no
  backports or patches. (An earlier draft required Rails 8.2, which isn't released.)
- **Dependencies:** `railties`, `actionpack`, `herb`, `reactionview`. No Node for apps.
- **Templates:** views, partials, ViewComponent sidecar templates, mailer previews. Not Phlex.
- **Installer:** generator sets up the ReActionView initializer, the Claude Code skill, `.mcp.json` and
  the gitignore.
- **Overlay:** small corner button with the note count, plus a shortcut.
- **Starting an edit:** Alt/Option-click opens the menu (changed 2026-11-09; it used to edit right away), and an edit-mode toggle edits with a normal click. Holding the key previews the element with the select cursor and highlight, except while typing, so nothing changes until a click. Alt-drag draws an area for a note, as dragging does in select mode.
- **Page update:** layered (decision 5), checked by a spike in phase 4.
- **Mixed text:** edit the source, Ruby and interpolation as locked chips.
- **Attributes:** editable in 0.1.
- **Translations:** edit the page's locale, other locales on demand. Keys found through markers in the
  I18n backend (from RESEARCH.md), not wrapper elements.
- **Markdown:** producers only (Kiln's content layer emits `data-md-source`).
- **Notes:** `tmp/tensaku/notes/`, elements and positions only (no screenshots), resolved with a reply,
  pruned later. Agents get them through files, `tensaku mcp`, clipboard and a skill.
- **Undo (changed 2026-11-13):** an undo and a redo stack for text saves (template text, attributes,
  translations, Markdown), per browser tab. Each save is an entry stored as data (what changed, from
  what, to what) in `sessionStorage`, so the stacks survive a reload and a Turbo visit. Undo reverts
  the latest save or a chosen one; redo applies the latest undone edit again; a new save clears the redo
  stack. Each step checks the source still holds the text it expects, and is refused otherwise.
  Cmd/Ctrl+Z and Cmd/Ctrl+Shift+Z (Ctrl+Y) work when nothing is being typed in and there is something
  to undo or redo. It was one undo per element, lost on reload, and a full stack was out of scope.
  A translation saved in several locales from one editor is one entry. Not covered: anything not
  saved through Tensaku.
- **Overlay:** TypeScript, compiled file committed.
- **Tests:** Minitest and Capybara with Cuprite. Features first, tests for the splicing and main flows.
- **Home (changed 2026-11-07):** a Lostcoords product. Public repo at github.com/lostcoords/tensaku,
  docs at tensaku.lostcoords.com, MIT.
- **Upstream:** build independently, talk to the Herb maintainers after 0.1.
- **Kiln:** Kiln's content layer renders with commonmarker and writes `data-md-source` when the app
  turns on source positions, and its build fails on Tensaku and Herb attributes. David accepted the
  Markdown HTML changes. See "Markdown contract" below.
- **MCP authentication (removed 2026-11-13):** the HTTP MCP endpoint took no token and relied on a
  loopback, `Origin` and `Host` check. `tensaku mcp` runs over stdio as a child of the agent, so there
  is no network endpoint to guard. Every endpoint the overlay calls still needs the token.
- **Herb attribute splats (added 2026-11-09):** Herb 0.11.2 drops attributes passed as
  `tag.div(**attrs)` when `action_view_helpers` is on (Herb issue #2737, open fix in PR #2768, neither
  resolved on 2026-11-09). Tensaku's `SourceAttributionVisitor` recommends that option, so installing
  Tensaku triggers the bug in development. Production and source writes aren't affected.
  - Decision (changed 2026-11-09): Tensaku keeps the option off by default. Pages silently broke (a
    Parcela docs search bar lost its `data-action`), which is worse than helpers like `link_to` losing
    their own stamps. `Tensaku::Railtie::SourceStamps` drops the recommendation, so Herb doesn't warn
    on every compile as it does when an app only sets the option to false. Apps can still opt in; the
    safety page documents it. We don't comment on or file anything in the Herb project.
  - When a Herb release has the fix: bump Herb, compile `<%= tag.div(**attrs) do %>x<% end %>` with
    the option on to confirm the attributes stay, then decide whether to use the stock visitor again.
- **Agent feedback (changed 2026-11-13):** the page shows what the agent does: a `working` status set by
  `start_note`, which agents are connected and which of them are listening, pushed to the page (see
  "Change events"). Each `tensaku mcp` process keeps a file in `tmp/tensaku/notes/.agents/` with the
  client's name, directory, start time and last tool call, touched every five seconds while it runs,
  and marked listening while a `watch_notes` call waits. Connected means touched in the last 20
  seconds. Editing a note sets it back to `open` and keeps its thread.
  - Agents button (changed 2026-11-13): the status moved from a green light on the tray and the corner
    button to a toolbar tool, a paper plane: grey, in ink, or flying in green ink, with no pulsing. Its
    popover says what each agent does, from the notes it started and its last call. A pulsing dot
    said only "listening", and two sessions of one agent looked the same.
  - Delivery: `watch_notes` sets `delivered_at` and `delivered_to`, so a card shows the note arrived,
    not only that it was saved. With a listener, the form's button names it.
  - Threads: lists and cards keep the agent's latest message and what follows. Every `watch_notes` call
    repeated whole threads into the agent's context.
  - A busy agent isn't in `watch_notes`. Once a session has called `watch_notes`, every other tool
    answer claims and includes the notes sent since it last looked (changed 2026-11-13; it used to name
    their ids only). A listening agent then waits in `watch_notes` only when it has nothing else to do,
    and a follow-up reaches it at its next Tensaku call, without anything specific to one agent. A
    session that never listened still gets only the ids, so an unrelated `get_note` claims nothing.
- **Change events (added 2026-11-13, replaces the page's poll):** `GET /__tensaku/events` streams
  server-sent events, one `changed` whenever the notes or the agents change, and the page loads the
  notes then. The change signal is `Notes.version`: the last row of the `changes` table plus the set of
  connected agents (see "Notes in SQLite"; it was the notes folder's mtime until then). A check-in with
  nothing new isn't a change. The endpoint takes
  the connection over with Rack hijack and serves it from its own thread, so a tab doesn't hold a Puma
  thread; a server without hijack answers 501 and the page polls every four seconds, as it does while
  the stream is down. Measured on the docs site: no requests while idle, and a new note on the page in
  about 220 ms. The poll used to send a request every one to four seconds per tab.
  - `watch_notes` reads the same version in a write transaction and scans the notes only when it
    changed.
  - The stream and `watch_notes` wait on the doorbell (see "Doorbell"); they checked four times a
    second until then.
  - The browser reads the stream with `fetch`, not `EventSource`, so the token stays in a header.
- **Notes in SQLite (added 2026-11-13, replaces the note files of "Notes" and "Notes and changing
  code"):** notes, their threads, connected agents, selections and a change log are tables in one
  SQLite database, `tensaku.sqlite3`. JSON files synced through git would have made every note change
  a commit and conflicts part of the history; the same schema can later sit behind a server, which is
  the step toward notes across machines. Not done: that server, or any sync.
  - Writes are `BEGIN IMMEDIATE` transactions in WAL mode with a five-second busy timeout. Claiming a
    note is one transaction, so two processes never get the same note (tested with `fork`). Notes no
    longer take `tmp/tensaku/write.lock`, which stays for source edits only.
  - Each app is a row in `projects`, by its real path, with its git origin; each note records the
    commit checked out when it was written. A worktree is its own path, so it starts with no notes.
  - One connection per process behind a re-entrant lock, opened again after a fork or when
    `TENSAKU_HOME` changes. Binary strings (ids from a request path) are bound as text, or SQLite
    compares them as blobs and finds nothing.
  - Notes from the file era aren't imported: Tensaku isn't released, so nobody has notes to keep.
  - Migrations (2026-11-13): `Store::SCHEMA` is the base as of `user_version` 2, and `MIGRATIONS` lists
    every later change in order, each applied once in the same immediate transaction that reads the
    version. A step that may have run is never changed. The first step adds `agents.version`.
  - Cost: the `sqlite3` gem, a native gem, for apps on Postgres or MySQL too. Agents can't edit notes
    as files; `tensaku notes` replaces that.
- **Data folder (added 2026-11-13):** the database is in the platform's per-user data folder
  (`~/Library/Application Support/tensaku`, `$XDG_DATA_HOME/tensaku`, `%LOCALAPPDATA%\tensaku`), or
  `TENSAKU_HOME`. Notes outlive a checkout, `git clean -x` and `tmp:clear`, and one database holds every
  app. The folder is created owner-only. Runtime state of one server stays in the app's `tmp/tensaku/`:
  the token, the source-edit lock and `mcp.log`.
- **Doorbell (added 2026-11-13):** a waiting process (a page's event stream, a `watch_notes` call)
  listens on a Unix socket in `/tmp/tensaku-UID/<hash of the app path>/`; a writer connects to each one
  after its transaction commits, and deletes the ones that refuse. The sockets are under `/tmp`, not the
  app or the data folder, because a socket path is limited to about 100 bytes. A waiting process also
  checks every ten seconds, for an agent that stopped checking in. Without Unix sockets, it checks every
  second. Measured on the docs site: a new note on the page in 40 to 70 ms, no requests while idle.
  SQLite can't notify other processes, and a file watcher would need the listen gem or native code.
- **Tensaku CLI (added 2026-11-13):** `tensaku notes` runs the MCP tools from a shell for agents
  without MCP, printing the same text. Each run is a session that checks in and leaves when done, so a
  note it starts is free again afterwards.
- **Archive (added 2026-11-13, replaces deleting closed notes):** resolved and declined notes move to
  the archive after `archive_after` (was `prune_after`) or with **Archive done** (was **Clear done**).
  They stay listable (`status: archived`) and come back when reopened. Once notes persist, what was
  resolved is history worth keeping. Deleting a single note still deletes it. The notes panel has an
  **Archive** tab, newest first, where a note can be reopened or deleted.
- **Picking the session (added 2026-11-13):** the note form and an open note's card have a **To**
  menu of the connected sessions by handle. A note sent to a session gets that session as its owner
  when it is written, so other sessions skip it in `watch_notes` and `list_notes` and can't start it,
  and the idle-first rule doesn't apply to it. Moving it to another session (or to anyone) clears the
  delivery and sends it again. `list_notes` marks each active note *Yours* or *Nobody's yet* and counts
  the notes other sessions hold. `resolve_note` refuses a note that isn't `working`, so an agent that
  skipped `start_note` fails loudly; editing files before that can't be stopped.
  Ownership lasts while the owner's process runs, not while it checked in within 20 seconds, so a
  slow check-in doesn't free a note mid-work.
- **Assign, not send (2026-11-13):** MCP is pull only, so in general Tensaku can't make an agent
  start a turn (Claude Code channels are the exception, below). So the page doesn't say "Send": a saved note is
  **Unassigned** until an agent takes it, or **Assigned to** one session from the **Assign to** menu
  (default **Anyone**). The card's **Assign** button reassigns an open note; on a note in progress it
  is **Reassign**, which takes the note back from a session that was stopped mid-work but still runs
  (open again; that session's resolve is refused because the note isn't `working`). A note in
  progress whose session's process ended is marked `stopped`: the card says anyone can take it, and
  `list_notes` warns that part of the change may already be in the file.
- **Claude Code channel (2026-11-13):** `tensaku mcp` declares `experimental["claude/channel"]` to
  clients whose name contains "claude". In a session started with
  `claude --dangerously-load-development-channels server:tensaku`, a `notifications/claude/channel`
  message starts a turn. A session without the flag drops it silently, and the server can't tell, so
  it sends a hello with a random code 1.5 s after `notifications/initialized` (Claude Code registers
  its listener a moment after connecting and drops earlier messages; seen in its debug log) and once
  more at 6 s, and only counts the channel as working when Claude calls `channel_ready` with the code.
  Then a thread waits on the doorbell, claims new notes for the session (`claim_sent`, so the
  idle-first and assignment rules apply) and pushes them as one message with `meta.kind = notes` and
  the ids. The session is shown as listening and **Live**. Verified end to end with Claude Code 2.1.323
  (Haiku): hello, `channel_ready`, a saved note declined by the agent about 1.5 s later.
  Not done: permission relay (`claude/channel/permission`), which would let the page approve tool
  use; anyone who can reply could approve, so it needs more thought.
- **Optimistic cards and refresh after an agent (2026-11-13):** a card's change (status, message,
  assignment) is applied to the local notes, pins, panel and open card before the PATCH, and put back
  with a toast if it fails; the open card is redrawn when a load brings a changed note, unless a field
  in it has text. `GET /notes` returns `changed_at`, the time of the latest agent message on a resolved
  note in the app; when it changes after the first load, the page refetches and morphs itself like
  after an edit, and adds stylesheets whose URL changed (digests) before removing the old ones.
- **Screenshots (added 2026-11-13):** when the note form opens, the overlay draws the area around the
  targets with modern-screenshot (MIT, bundled, pinned) and uploads it once the note is saved, as a PNG
  in a `screenshots` table (schema version 2; migrations now run in steps). Drawing the DOM needs no
  permission and no extension, unlike `getDisplayMedia`, and leaves the overlay out with a filter. It
  draws the smallest element that contains the area plus a margin, then crops; a canvas is limited to
  16000 px a side and 40 million pixels, past which the scale drops. Measured in Chromium and WebKit
  (2026-11-13): about 0.6 s for a heading on the docs site (731 elements), in the background while
  the form is open. A container with more than 2000 elements is drawn as the smallest element around
  the target, without the margin: one row of a 20,000-element page took 4 to 24 ms, where drawing the
  page took 15 to 20 s and came out at a useless scale. An image from another origin without CORS
  headers is left blank; a same-origin one shows. Up to 4 MB per note. Agents get it as an MCP image (`get_screenshot`) or a file
  (`tensaku notes screenshot`). modern-screenshot adds about 36 KB to the overlay script.
- **Agent liveness and placement (added 2026-11-13):**
  - A session holds an exclusive `flock` on `sessions/<session>.lock` in the data folder while it
    runs; it is alive exactly while that lock is held, and stops owning its notes the moment its process
    ends. A process id was used first, but the system can give a crashed agent's id to a new process,
    which would keep its notes stuck until the row was pruned a day later.
  - Code fingerprint (`Tensaku::Build`): a digest of Tensaku's Ruby files, taken when a process
    starts. The dev server answers `restart: true` on `GET /notes` when its fingerprint differs from the
    files on disk, and the page says to restart it: the page loads the overlay script fresh on every
    request, so a stale server answered new requests with old code ("Not found" for the screenshot
    upload). Each agent's check-in records its fingerprint, and the Agents popover marks an agent whose
    fingerprint differs as running older code.
  - A session working on a note leaves new notes to a listening session working on none; with nobody
    idle, it takes them.
  - A session's handle is the first word pair no other connected session of the app has.
  - Every agent serving an app is listed on its page, with the folder it runs in, including one that
    found the app below a repo root. Hiding those (tried the same day) left a person who runs agents
    at the repo root with no session to send a note to.
  - Each browser tab keeps its own selection; `current_selection` returns the newest.
- **MCP call log (added 2026-11-13):** `tensaku mcp` appends one JSON line per tool call to
  `tmp/tensaku/mcp.log` in each app: session handle, agent, tool, milliseconds, answer bytes, notes
  handed over, error. It moves to `mcp.log.1` past 1 MB. Claude Code transcripts showed every Tensaku
  call but `watch_notes` takes under a second; the log keeps that measurable for any agent.
- **Agents connect over stdio (changed 2026-11-13, replaces the HTTP MCP endpoint and `tensaku AGENT`):**
  - `tensaku mcp` is an MCP server over stdio. The agent starts it from its project config
    (`.mcp.json` for Claude Code, and each other agent's own file). It loads `tensaku` and Active Support,
    not the Rails app, and reads and writes the note files under the same file lock as the dev server
    (the database since 2026-11-13, see "Notes in SQLite").
  - The note files are the only link between the dev server and the agent. Neither needs the other
    running, no port is configured, and the checkout the agent runs in decides which notes it sees. That
    covers several apps and Parcela-style worktrees, where each checkout has its own dev server on its
    own port and its own `tmp/`.
  - Finding the app: `--app PATH`, else the nearest directory above the working directory with
    `config/application.rb`, else apps up to two levels below it whose `Gemfile.lock` lists tensaku.
    With several apps, the tools cover all of them and each note names its app. Note ids are random, so
    tools that take an id need no app.
  - The dev server writes the page's base URL (as the browser sent it) to `tmp/tensaku/server.json`, so
    the agent gets full page URLs. Nothing depends on the server being up.
  - Waking an agent: none. MCP can't start a turn, and every way around that is tied to one agent or to
    its terminal. A note reaches an agent that waits in `watch_notes`, or the next time you ask an agent
    to look. Both are plain MCP and work the same in every agent.
  - Files over sockets: the files are already the record, survive restarts of either side, and need no
    discovery. The page gets change events from the dev server (see "Change events"), which watches
    the files.
  - Removed with it: the HTTP endpoint and its loopback-only check, `Mcp-Session-Id` handling, the
    nameless `.agent` file, `.listeners/`, `config.notes_path`, and `bundle exec tensaku AGENT`, which
    typed into the agent's terminal (2026-11-10 to 2026-11-13). Typing could answer a permission dialog,
    and needing a wrapper to use Tensaku was the wrong shape.
  - Not done: spawning agents from the page (Pinagent's model). It needs worktrees, cost limits and a
    permission mode, and the page token is readable by any script on the page, so a compromised
    dependency could start an agent. ACP starts agents too, so it is left out for the same reason.
- **Declined notes (added 2026-11-10):** `decline_note` closes a note with a reason. Before, an agent
  that wouldn't make a change could only resolve the note, which turned the pin green.
- **Note moves (removed 2026-11-10):** a card no longer moves its note to another element, and `PATCH
  /notes/:id` no longer takes `targets`. A note whose element is gone says so; write a new one. Card
  buttons are Mark as done (Reopen once done), Edit, Delete.
- **Context on targets (added 2026-11-10):** targets carry the element's own classes (at most 12).
  Computed styles, screenshots and console logs stay out: the agent can open the page itself.
- **MCP sessions (changed 2026-11-13):** one `tensaku mcp` process is one session. It takes its name
  from `clientInfo` at `initialize`. Which session may work on a note is "Note ownership" below.
- **Note ownership (added 2026-11-13, replaces the `start_note` rule in "MCP sessions"):** a note
  belongs to one session. `watch_notes` claims each note it hands over: it writes `session`, `agent`,
  `delivered_at` and `delivered_to` in the same locked step as the scan (`Notes.claim_sent`), so two
  listeners polling at once never both get a note. `start_note` claims it too. While the owner is
  connected, other sessions don't see the note in `watch_notes` or `list_notes`, and `start_note`,
  `resolve_note` and the other changes refuse it in any status. A note whose owner is gone can be
  taken by anyone. A request for changes on a resolved note keeps its owner, so it goes back to the
  session that made the change, which knows the context. Before this, every listener got every note,
  and a slower one could redo a note another had resolved.
  - Handles: each session gets two words from its session id, such as amber-fox, kept in its agent
    file. Notes and the page name an agent "Claude Code · amber-fox", the first `watch_notes` and
    `start_note` answers tell the agent, and the instructions ask it to tell the person, so a terminal
    can be matched to a row. Every session of one client used to show as "Claude Code".
  - The Agents popover lists listening sessions first, with folder and last action, and folds the
    rest into "N more connected, not listening".
  - Not yet: picking the session a note goes to. With several listeners, the first to look takes it.
- **Threads (added 2026-11-07):** a note keeps `thread`, a list of messages from you or the agent.
- **Stale check (refined 2026-11-07):** the server's byte comparison plus an overlay check that the
  file's static text still matches the rendered element when the editor opens.
- **Request checks (added 2026-11-08):** every endpoint checks the raw `Host` (local names, loopback
  IPs, or names in `config.hosts`) and `Origin`, and refuses requests whose proxy headers name a
  non-loopback client. The token goes only into 2xx and 422 pages with a local `Host`, whole documents
  or fragments the browser loads as a page or frame. Tunnels and containers are unsupported.
- **Shared state (added 2026-11-08):** the token lives in `tmp/tensaku/token` and the overlay's
  selection in the notes directory, so Puma workers agree. Saves and note changes run under one
  `flock` in `tmp/tensaku/write.lock`, re-reading the file inside it.
- **Markdown contract (changed 2026-11-08):** producers write `data-md-source` (was `data-tensaku-md`),
  so Kiln and Tensaku don't reference each other. Kiln's content layer is off until the app turns on
  `Kiln::Content.source_positions`, and Tensaku no longer adds `Kiln::Content.root` to the writable
  paths: the app lists it. Tensaku edits a subset of the blocks Kiln marks (`p`, headings, `li`,
  `blockquote`, whole lists); `pre`, `table` and `hr` only get notes.

## Open questions

None right now.
