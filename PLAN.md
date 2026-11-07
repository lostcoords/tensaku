# Tensaku — plan

Tensaku (添削, correcting a draft) lets you fix a running Rails app from the page itself, in development.
Click a piece of text and edit it in place, and Tensaku writes the change back to the template, the
locale file or the Markdown source. Or leave a note on an element or an area of the page, and your coding
agent reads it with the exact file and line attached, instead of a screenshot and "change this".

Status: planned, all questions answered (see the decisions log at the end). Nothing is implemented yet.
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

- [ ] Gem skeleton, MIT license, README.
- [ ] `test/dummy` Rails 8.1 app with ReActionView (development group), Turbo, Stimulus, a ViewComponent
      and a mailer preview.
- [ ] Minitest, Capybara with Cuprite for browser tests.
- [ ] TypeScript build for the overlay (esbuild or bun), compiled file committed.
- [ ] Lint (rubocop-rails-omakase) and GitHub Actions CI, actions pinned to commit SHAs.
- [ ] jj repo, colocated. Public repo at github.com/davafons/tensaku.
- [ ] Claim the `tensaku` name on RubyGems with a 0.0.1 placeholder (ask before `gem push`).

### Phase 1 — references

- [ ] Railtie: ReActionView interception and `SourceAttributionVisitor` in development only.
- [ ] Middleware injects the overlay.
- [ ] Corner button with note count, keyboard shortcut.
- [ ] Check that ViewComponent sidecar templates get stamps.
- [ ] Overlay: hover highlight, click to copy a reference with partial chain, Stimulus controller and
      Turbo Frame.

### Phase 2 — notes

- [ ] Note format and storage in `tmp/tensaku/notes/`.
- [ ] Element and area selection, comment box, pins, notes panel.
- [ ] Resolve and dismiss from the page, prune old resolved notes.

### Phase 3 — notes for agents

- [ ] Copy one or all notes as Markdown.
- [ ] MCP endpoint.
- [ ] Claude Code skill.
- [ ] Install generator.

### Phase 4 — editing templates

- [ ] Spike: page update strategies on Hotwire, Turbo Frames and no-Turbo pages (decision 5).
- [ ] Guard: loopback, token, allow-list.
- [ ] Source pieces from an element stamp, text and attribute splices, stale-file check.
- [ ] Cache clearing after writes, fragment-cache warning.
- [ ] Overlay: Alt-click and edit mode, locked chips, attribute form, save, one-step undo.
- [ ] Mailer previews.
- [ ] Page update: same-source nodes, refetch and morph, POST pages, Herb live patching when present.

### Phase 5 — translations

- [ ] I18n backend markers (key and locale), stripped by the overlay, text and attributes.
- [ ] YAML scalar splice that keeps quoting and comments.
- [ ] Other-locale toggle.

### Phase 6 — Markdown

- [x] Kiln emits `data-tensaku-md` (done in Kiln, unreleased, see Kiln's PLAN.md "Tensaku support").
- [ ] Markdown splice. Kiln's headings contain a generated empty `<a class="anchor">`; text extraction
      ignores children without text.

### Phase 7 — adopt

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
- **Kiln:** done in Kiln (unreleased, 0.1.1): the build fails on `data-herb-*`/`data-tensaku-*`, and the
  content layer moved to commonmarker and emits `data-tensaku-md` in development when Tensaku is loaded.
  David accepted the Markdown HTML changes.

## Open questions

None right now.
