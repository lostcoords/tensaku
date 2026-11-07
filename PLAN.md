# Tensaku — plan

Tensaku (添削, correcting a draft) lets you fix a running Rails app from the page itself, in development.
Click a piece of text and edit it in place, and Tensaku writes the change back to the template, the
locale file or the Markdown source. Or leave a note on an element or an area of the page, and your coding
agent reads it with the exact file and line attached, instead of a screenshot and "change this".

Status: phases 0 to 6 implemented and tested locally (2026-11-07), unreleased. Not yet public: the GitHub
repo, the RubyGems name and phase 7 wait for approval. See the Findings under each phase.
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
| Agentation, Pinpoint, Vibe Annotations, UI Annotator MCP, CommentKit | Annotation tools for coding agents, several with MCP. | They find source through React internals or JS source maps. On a Rails page they only see selectors. None edits text. |
| [Tidewave](https://tidewave.ai) | Point-and-click prompting for its own agent. The `tidewave` gem is a free MCP server (eval, SQL, docs). | The browser toolbar is paid and tied to Tidewave's agent. No in-page editing. |
| rails-i18n-onair, i18n_proofreading, i18n_viz, i18n-edit | Edit or suggest translations in the page. | Translations only. Mostly old. Some store translations in a database instead of YAML. |

Tensaku is the missing layer on top of Herb: write-back for template text, attributes, translations and
Markdown, plus notes with exact positions that an agent can read.

## Core decisions

### 1. Built on Herb, through ReActionView, in development only

- Rails 8.1+. Rails 8.1 has no Herb template handler, so Tensaku depends on
  [ReActionView](https://github.com/marcoroth/reactionview), which provides one and lets other gems add
  Herb visitors (`config.engine.visitors.use(...)`).
- **Nothing changes in production.** Tensaku and ReActionView go in the `development` group, so
  production (and Kiln builds, which run in production) keep rendering with Erubi. No backports, no
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
- Write endpoints accept requests from loopback addresses only, and need a per-boot token that is
  embedded in the page.
- Writes are limited to an allow-list: `app/views`, `app/components`, `config/locales`, and paths that
  other gems register (for example Kiln's `content/`).
- Kiln fails a build if any `data-herb-*` or `data-tensaku-*` attribute reaches the output.

### 3. The editor edits the source, never the rendered text

- Text nodes aren't stamped. Tensaku finds them from the parent element's stamp: the server re-parses
  the file with Herb, finds the element at that position, and returns its children as source pieces.
- Mixed text like `Hello <%= user.name %>!` is one text node in the browser ("Hello David!") and three
  pieces in the file. The editor shows `Hello [user.name]!`, with the Ruby as a locked chip, and you edit
  the static parts. The same applies to translation interpolation (`Hello [%{name}]`), HTML entities and
  inline Markdown.
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
- Undo: version control is the history. The overlay also keeps the last edit per element, so a mistake
  can be undone with one click (same stale-file check).

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

A spike at the start of phase 4 tries this on a Hotwire page, a page with Turbo Frames and a page
without Turbo before the overlay depends on it.

### 6. Two kinds of marks: edits and notes

Like Japanese proofreading, which marks definite corrections in red (赤字, *akaji*) and questions for
the author in pencil (鉛筆, *enpitsu*):

- **Edit:** you change the text yourself, and the file changes. Only for text with a known, writable
  source.
- **Note:** you describe what should change ("too much spacing", "rename this section"), and an agent
  does it. Works on anything on the page, including text that comes from Ruby data.

### 7. Notes are local files the agent can read

- One JSON file per note in `tmp/tensaku/notes/`: local, ignored by git, cleared by `tmp:clear`. Notes
  are short-lived instructions, not project history.
- A note holds the URL, the comment, every target's file, range, kind and text, the rectangle and
  viewport for area notes, a status and a reply. No screenshots: the agent can take its own with a
  browser tool.
- Lifecycle: `open` → `resolved` with a short reply from the agent or you ("changed the heading in
  `_hero.html.erb:4`"). The agent can also set `question` with a reply when the note is unclear, and the
  pin shows the question on the page. Resolved pins turn green so you can check the change, then you dismiss them or
  they're deleted after a few days.
- Four ways for agents to get notes, all in 0.1:
  - **Files:** agents read `tmp/tensaku/notes/*.json` directly.
  - **MCP endpoint** on the dev server: `list_notes`, `get_note`, `resolve_note`, `ask_question`,
    `watch_notes` (waits for new notes, so an agent can work through them as you add them),
    `current_selection`. Modeled on Agentation's MCP (see RESEARCH.md).
  - **Copy to clipboard:** one note or all open notes as Markdown, for any chat.
  - **Claude Code skill** shipped with the gem: how to find, act on and resolve notes.

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
  "reply": null,
  "created_at": "2026-11-07T18:00:00Z"
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
| `data-tensaku-md="path:line:col-line:col"` | Kiln (or another Markdown producer), development only | Block's Markdown source range |
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
| Notes for agents | 3 | Files, MCP endpoint, copy to clipboard, Claude Code skill. |
| Edit template text | 4 | Alt/Option-click a text node to edit it right away, or turn on edit mode from the toolbar to see every editable text highlighted and edit with a normal click. Save on Enter or blur. Ruby shows as locked chips. |
| Edit attribute text | 4 | `alt`, `title`, `placeholder`, `aria-label`, button `value`: a small form per element. |
| One-step undo | 4 | Undo the last edit per element. |
| Page update after saving | 4 | Decision 5. |
| Edit translations | 5 | Edits the page's locale. A toggle shows the same key in the other locales, to update them together or see they're out of date. |
| Edit Markdown | 6 | Through `data-tensaku-md` from Kiln's content layer. |
| Corner button and shortcut | 1 | A small draggable button in a corner with the open-note count, plus a keyboard shortcut to toggle the overlay. Pins show whenever notes exist. |
| ViewComponent templates | 1 | Sidecar `.html.erb` templates compile through Herb, so references, notes and edits work. Inline templates (`erb_template` in Ruby) don't. |
| Mailer previews | 4 | Edit HTML email templates from `/rails/mailers` previews. Needs a test that previews render through Herb. |
| Install generator | 3 | `bin/rails generate tensaku:install`: Gemfile group check, ReActionView initializer, Claude Code skill in `.claude/skills/tensaku/`, MCP endpoint in `.mcp.json`, `tmp/` ignored. Prints what it changed. |
| Open in editor | — | Herb's dev tools already do this. Not rebuilt. |

### Out of scope

- Editing text that comes from Ruby data (`@post.title`). It gets notes and a reference to the ERB
  expression, not editing.
- Rich text editing (bold, links, splitting paragraphs). One text node at a time.
- Rendering Markdown. Producers like Kiln do that.
- Phlex views (Ruby, not ERB, so Herb can't stamp them).
- Anything in production or test.
- Any environment other than development. No staging editor, no hosted service, no accounts.
- Several people editing at the same time.
- A full undo stack across edits. Version control covers history.

## Shape

```
lib/tensaku.rb                  entry point, configuration
lib/tensaku/railtie.rb          dev-only: ReActionView interception, visitor, middleware
lib/generators/tensaku/         install generator
lib/tensaku/middleware.rb       injects the overlay and request meta, serves the endpoints
lib/tensaku/guard.rb            loopback check, boot token, path allow-list
lib/tensaku/source/template.rb  text and attribute pieces from an element stamp, splice
lib/tensaku/source/locale.rb    find a YAML scalar by key, splice its value
lib/tensaku/source/markdown.rb  splice inside a producer's block range
lib/tensaku/i18n.rb             I18n backend that adds key markers in development
lib/tensaku/caches.rb           clears template caches and reloads I18n after a write
lib/tensaku/notes.rb            note files: write, list, resolve, prune
lib/tensaku/mcp.rb              MCP endpoint
skills/tensaku/SKILL.md         Claude Code skill
app/javascript/tensaku/         overlay source (TypeScript)
app/assets/tensaku.js           compiled overlay, committed
test/dummy/                     Rails 8.1 app used by the test suite
```

## Work list

Features first. Tests cover the splicing (where a bug corrupts files) and the main flows, without
chasing coverage.

### Phase 0 — workspace

- [x] Gem skeleton, MIT license, README.
- [x] `test/dummy` Rails 8.1 app with ReActionView (development group), Turbo, Stimulus, a ViewComponent
      and a mailer preview.
- [x] Minitest, Capybara with Cuprite for browser tests.
- [x] TypeScript build for the overlay (esbuild or bun), compiled file committed.
- [x] Lint (rubocop-rails-omakase) and GitHub Actions CI, actions pinned to commit SHAs.
- [x] jj repo, colocated. Public repo at github.com/davafons/tensaku.
- [ ] Claim the `tensaku` name on RubyGems with a 0.0.1 placeholder (ask before `gem push`).

Findings (2026-11-07):

- The jj repo is colocated; the public GitHub repo isn't created yet (waiting for approval), so CI
  hasn't run on GitHub. `bin/lint` and `bin/test` pass locally. `gem build` packages the right files.
- Spike before building on it: ReActionView 0.6.1 plus `SourceAttributionVisitor` stamps layouts,
  views, partials rendered in a loop, `link_to` (through `action_view_helpers`, which the visitor turns
  on by itself) and ViewComponent sidecar templates on Rails 8.1.4.1. Mailer previews render through
  Herb with no extra work.
- Herb positions are 1-based lines and 0-based character columns (stamps add 1); token ranges are byte
  offsets. Psych columns are characters too. Kiln's `data-tensaku-md` columns are bytes. Every splice
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

- [x] Railtie: ReActionView interception and `SourceAttributionVisitor` in development only.
- [x] Middleware injects the overlay.
- [x] Corner button with note count, keyboard shortcut.
- [x] Check that ViewComponent sidecar templates get stamps.
- [x] Overlay: hover highlight, click to copy a reference with partial chain, Stimulus controller and
      Turbo Frame.

Findings: the overlay lives in a shadow root on an element attached to `<html>`, outside `<body>`, so
Turbo body swaps and the morph never touch it. The default shortcut is Alt+Shift+T
(`config.shortcut`). ReActionView's debug mode (Herb dev tools) wraps ERB output in
`display: contents` spans; the overlay treats them as part of the parent element's text.

### Phase 2 — notes

- [x] Note format and storage in `tmp/tensaku/notes/`.
- [x] Element and area selection, comment box, pins, notes panel.
- [x] Resolve and dismiss from the page, prune old resolved notes.

Findings: block elements span the whole line, so an area note measures each element's content extent
(a range over its children) and keeps elements that are at least half inside the rectangle, outermost
first. Notes without targets show in the panel only, with no pin. Text-selection notes (kind `text`)
come from selecting text before clicking in select mode. Answering a question appends the answer to
the comment and sets the note back to open.

### Phase 3 — notes for agents

- [x] Copy one or all notes as Markdown.
- [x] MCP endpoint.
- [x] Claude Code skill.
- [x] Install generator.

Findings: MCP clients configured in `.mcp.json` can't read the page's boot token, so the MCP endpoint
takes no token. It answers loopback addresses only and refuses a foreign `Origin` or a non-local `Host`
(so a web page can't reach it, including through DNS rebinding). It only reads and updates notes, never
source files. See the decisions log. `watch_notes` long-polls up to 300 seconds and holds a server
thread while it waits.

### Phase 4 — editing templates

- [x] Spike: page update strategies on Hotwire, Turbo Frames and no-Turbo pages (decision 5).
- [x] Guard: loopback, token, allow-list.
- [x] Source pieces from an element stamp, text and attribute splices, stale-file check.
- [x] Cache clearing after writes, fragment-cache warning.
- [x] Overlay: Alt-click and edit mode, locked chips, attribute form, save, one-step undo.
- [x] Mailer previews.
- [x] Page update: same-source nodes, refetch and morph, POST pages, Herb live patching when present.

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

- [x] I18n backend markers (key and locale), stripped by the overlay, text and attributes.
- [x] YAML scalar splice that keeps quoting and comments.
- [x] Other-locale toggle.

Findings: markers are invisible: U+2063, then "locale:key" in base 4 with four zero-width characters,
then U+2063. They're added only while a controller handles an HTML request, never to `number.*`,
`date.*`, `time.*` and similar keys, never to a value from `default:`, and never to pluralized lookups
(so `count:` translations aren't edited in the page). The middleware strips them from non-HTML
responses and from `<script>` and `<style>`. A Ruby comparison with a translated string sees the
marker in development. Every YAML write is verified by loading the result before the file is
replaced; a plain scalar that would change meaning is written double-quoted; `%{...}` placeholders
must stay the same.

### Phase 6 — Markdown

- [x] Kiln emits `data-tensaku-md` (done in Kiln, unreleased, see Kiln's PLAN.md "Tensaku support").
- [x] Markdown splice.

Findings: Kiln's headings no longer contain an anchor link (`<h2 id="slug">Text</h2>`), so nothing
needs ignoring. `data-tensaku-md` columns are commonmarker's byte columns, end inclusive. Heading
hashes, list markers and quote markers are locked; the rest of the block is edited as Markdown
source. `p`, headings, `li` and `blockquote` are editable; lists, tables and code only get notes.
Kiln's `Kiln::Content.root` is writable automatically when Kiln's content layer is loaded, with no
Kiln change. Tested with a stand-in producer in the dummy app, not yet against Kiln itself.

### Phase 7 — adopt

- [x] Tensaku's own docs site (`docs/`), added 2026-11-07 as the first place Tensaku runs on a real
  site before it goes into other apps.

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
  Kiln's page comparison catches drift on static sites.
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
- **Separate gem**, not part of Kiln. Kiln doesn't carry Herb, and server-rendered apps like wariwari use
  Tensaku without a static exporter.
- **Rails:** 8.1+, Herb through ReActionView. Development only: production keeps Erubi, with no
  backports or patches. (An earlier draft required Rails 8.2, which isn't released.)
- **Dependencies:** `railties`, `actionpack`, `herb`, `reactionview`. No Node for apps.
- **Templates:** views, partials, ViewComponent sidecar templates, mailer previews. Not Phlex.
- **Installer:** generator sets up the ReActionView initializer, the Claude Code skill, `.mcp.json` and
  the gitignore.
- **Overlay:** small corner button with the note count, plus a shortcut.
- **Starting an edit:** both Alt/Option-click and an edit-mode toggle.
- **Page update:** layered (decision 5), checked by a spike in phase 4.
- **Mixed text:** edit the source, Ruby and interpolation as locked chips.
- **Attributes:** editable in 0.1.
- **Translations:** edit the page's locale, other locales on demand. Keys found through markers in the
  I18n backend (from RESEARCH.md), not wrapper elements.
- **Markdown:** producers only (Kiln's content layer emits `data-tensaku-md`).
- **Notes:** `tmp/tensaku/notes/`, elements and positions only (no screenshots), resolved with a reply,
  pruned later. Agents get them through files, MCP, clipboard and a Claude Code skill.
- **Undo:** version control plus one-step undo in the overlay.
- **Overlay:** TypeScript, compiled file committed.
- **Tests:** Minitest and Capybara with Cuprite. Features first, tests for the splicing and main flows.
- **Home:** public repo at github.com/davafons/tensaku, MIT.
- **Upstream:** build independently, talk to the Herb maintainers after 0.1.
- **Kiln:** done in Kiln 0.1.1: the build fails on `data-herb-*`/`data-tensaku-*`, and the
  content layer moved to commonmarker and emits `data-tensaku-md` in development when Tensaku is loaded.
  David accepted the Markdown HTML changes.

- **MCP authentication (changed 2026-11-07):** the MCP endpoint takes no boot token, because MCP clients
  can't read it from the page. Loopback only, plus refusing a foreign `Origin` or non-local `Host`.
  It reads and updates notes, never source files. Every endpoint the overlay calls still needs the
  token.
- **Stale check (refined 2026-11-07):** the server's byte comparison plus an overlay check that the
  file's static text still matches the rendered element when the editor opens.

## Open questions

None right now.
