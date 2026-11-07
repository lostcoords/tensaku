# Tensaku — prior art and related work

State as of 2026-11-07. GitHub facts were checked through the GitHub API (repos, issues, PRs, release
notes, code search). Everything else comes from web search and page fetches. *(unverified)* marks
claims that only come from secondary sources. X, Bluesky and Mastodon weren't searchable.

## Summary

- **Herb is not building browser → file editing or agent notes.** Nothing shipped, announced or on a
  roadmap. Its direction is linting, dev tools, a file → browser dev server and reactive views.
- **Rails 8.2 takes Herb's engine**, but not source attribution, dev tools or anything for agents.
- **Rails has two separate kinds of prior art, and nobody has combined them:**
  - Click-to-source and agent toolbars (Tidewave, Agentation ports). They map elements by selector or
    by the filename comments Rails adds, so file at best.
  - In-page i18n editors (i18n-edit, i18n_proofreading). They map text to a translation key with
    markers.
- **No project outside Herb itself uses `data-herb-source`.**
- **Across frameworks, attributes added at compile time with `file:line:col` have won** (Astro, Vue,
  Svelte, code-inspector, Onlook). That's the same approach as `data-herb-source`.

## 1. Herb and ReActionView

### Shipped

- **`SourceAttributionVisitor`** (Herb 0.11.0, 2026-09-24; PRs
  [#2447](https://github.com/marcoroth/herb/pull/2447), [#2611](https://github.com/marcoroth/herb/pull/2611),
  [docs](https://github.com/marcoroth/herb/blob/main/docs/docs/projects/engine/visitors/source-attribution.md)).
  - Built for linting the rendered page: "so a finding about the rendered page can be pointed back at
    the line that produced it." Used by Herb's browser linter and the dev tools panel.
  - The attribute name can be changed (`attribute:`).
  - Helpers like `link_to` are stamped at their `<%=` position, but only with the
    `action_view_helpers` parser option.
  - Inlined partials carry their own file.
  - **Elements rendered in a loop all carry the line they were written at.** Editing one edits all of
    them.
  - **HTML built in Ruby (helpers, `t()`) is not stamped.** Translations need their own marking.
  - The docs say to strip the stamps before reporting positions back, and to leave the visitor out of
    anything but a development build.
- **Dev Tools** (`@herb-tools/dev-tools`, since 0.7, [docs](https://herb-tools.dev/projects/dev-tools)).
  - Template outlines, "Open in Editor" (VS Code, Cursor, Zed, RubyMine), and a diagnostics panel with
    a JS `report()` API (0.11).
  - The docs say of autofix: "Nothing about `fix` is ever applied to the page or to the file on disk."
    Nothing writes to source.
- **Herb Dev Server** (0.10, [#1662](https://github.com/marcoroth/herb/pull/1662)).
  - File → browser only.
  - 0.11 added tiered hot reload ([#2516](https://github.com/marcoroth/herb/pull/2516)): applies
    whitespace, static and state changes without a reload, keeping focus, caret and unsaved input.
  - The docs call it experimental.
- **[ReActionView](https://reactionview.dev/) 0.6** is now a reactive-templates project (`herb:state`,
  `herb:slots`, server mode). Nothing about editing or AI.

### Proposals

- [herb#1755 "Herb MCP – a proposal"](https://github.com/marcoroth/herb/issues/1755) (2026-05-26, by
  Lucian Ghinda). Static-analysis tools for agents (`render_graph`, `unresolved_renders`, ...). No reply
  from the maintainer. It's the only AI, MCP or LLM item in either repo, and it isn't about the UI.
- No issues or PRs mention "visual editing", "edit in browser", "write back" or "contenteditable".
  GitHub Discussions are off on both repos.

### Talks

- Rails World 2026,
  ["Herb in Rails 8.2: Your ERB views, now HTML-aware"](https://www.rubyevents.org/talks/herb-in-rails-8-2-your-erb-views-now-html-aware):
  a linter, formatter, language server, browser dev tools and a dev server.
- Kaigi on Rails 2026
  [slides](https://speakerdeck.com/marcoroth/herb-in-rails-8-dot-2-your-erb-views-now-html-aware-at-kaigi-on-rails-2026-tokyo-japan).
  - Possible future work listed: "Offline Mode, React Components, Herb Components for gems,
    Client-side routing."
  - Many slides are images, so this is partial.
- Marco Roth's [other talks](https://www.rubyevents.org/speakers/marco-roth) ("Reactive Rails Views, No
  Rewrite Required") point at reactivity.
- He was on an
  [AI panel at Deccan Queen on Rails 2026](https://www.rubyevents.org/talks/panel-ruby-and-rails-in-the-ai-age-what-does-the-future-hold).
  No transcript.

**What this means for Tensaku:** no overlap with anything announced. The closest neighbor is Herb's
rendered-page linting, which uses the same stamps. Herb could still move this way, since it has most of
the foundation.

## 2. Rails core

- Herb merged as an ERB implementation: [rails#58552](https://github.com/rails/rails/pull/58552)
  (2026-08-25).
- `config.action_view.erb_implementation = :herb` is the 8.2 framework default for HTML templates, with
  `:erubi` to opt out: [rails#58721](https://github.com/rails/rails/pull/58721) (2026-09-24).
- Follow-ups: [#58770](https://github.com/rails/rails/pull/58770) (`herb:check`),
  [#59602](https://github.com/rails/rails/pull/59602) (template lines in syntax errors),
  [#59137](https://github.com/rails/rails/pull/59137) (open).
- Rails doesn't turn on source attribution. That's left to tools like Tensaku.
- AI in Rails core:
  - An AGENTS.md for the Rails repo itself was merged
    ([#55991](https://github.com/rails/rails/pull/55991)).
  - Generating AGENTS.md in new apps was rejected twice
    ([#57286](https://github.com/rails/rails/pull/57286),
    [#58987](https://github.com/rails/rails/pull/58987)).
  - "Add AI prompt to debug exception pages" is open
    ([#56826](https://github.com/rails/rails/pull/56826)).
- No Rails MCP in core. Community ones: [rails-mcp-server](https://github.com/maquina-app/rails-mcp-server),
  [rails-ai-context](https://github.com/crisnahine/rails-ai-context),
  [Tidewave Rails](https://github.com/tidewave-ai/tidewave_rails).
- `annotate_rendered_view_with_filenames` (HTML comments, file only, no line) hasn't changed since it
  became the development default in 2023 ([#50436](https://github.com/rails/rails/pull/50436)).

## 3. Projects

The catalog of related projects (click to source, agent toolbars, editing in the page, translations,
Rails agent tooling) is in [REFERENCES.md](REFERENCES.md). No Rails gem writes edits back to ERB.

## 4. Threads

- [Tidewave Web: in-browser coding agent for Rails and Phoenix](https://news.ycombinator.com/item?id=44960316)
  (HN, 299 points, Aug 2025). The main Rails thread about agents in the browser.
- [Show HN: Onlook](https://news.ycombinator.com/item?id=44127653) (408 points) and
  [the earlier "local-first Webflow for your own app"](https://news.ycombinator.com/item?id=41390449).
- [Ask HN: Injecting a visual editor into existing codebases](https://news.ycombinator.com/item?id=37946931)
  (2023).
- [Show HN: Stagewise](https://news.ycombinator.com/item?id=44798553).
- [Show HN: React Grab](https://news.ycombinator.com/item?id=46035872). Agentation:
  [1](https://news.ycombinator.com/item?id=46713140), [2](https://news.ycombinator.com/item?id=47202600).
- [Show HN: Ctrl-click text to jump to its translation key](https://news.ycombinator.com/item?id=47144995).
- [Herb: HTML-aware ERB parsing and tooling](https://news.ycombinator.com/item?id=43704853) (HN, 119
  points, Apr 2025).
- Rails forum:
  [Prompt for AI agents on debug pages](https://discuss.rubyonrails.org/t/proposal-add-prompt-for-ai-agents-block-to-debug-exception-pages-pr-open/90157).
- [Adopting Herb at GitHub](https://hawksley.org/2026/05/06/adopting-herb-at-github.html) (Joel
  Hawksley).
- Not found: any r/rails, Ruby Weekly or X/Bluesky thread about editing ERB or translations in the
  browser with write-back, or about notes on a Rails UI for agents.

## Techniques to borrow

1. **Translation keys: markers in the I18n backend** (i18n_proofreading). In development, append a
   marker with the key to each translated string and strip it in the overlay.
   - Works inside attributes too, which a wrapper element can't.
   - Their rules: never on `number.*` or `date.*`, never on keyless `default:`.
   - Invisible zero-width characters (Sanity, Vercel) are an alternative, but they break string
     comparisons in Ruby unless every comparison cleans them first.
   - Changes PLAN decision for translations, see below.
2. **Loops:** elements rendered in a loop share one stamp. The editor says "this edits all N copies".
3. **YAML:** keep comments and ordering. i18n-edit losing comments is the known failure.
4. **Round trip:** prefer Herb's hot reload when it runs. It keeps focus, caret and unsaved input.
5. **Notes:** Agentation's model is the reference: click, text or area selection, a Markdown fallback,
   MCP with pending, resolve and watch, and a status where the agent can ask a question back. Add exact
   `file:line`, which none of the selector-based tools have.
6. **Grouping:** an explicit attribute to widen a highlight to a parent (`data-vercel-edit-target`,
   `data-sanity-edit-group`) for cases the automatic mapping gets wrong.
7. **Safety:** development only, CSRF and token, writes limited to an allow-list, a startup error
   outside reloading environments (like Tidewave).
