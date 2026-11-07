# Tensaku — references

Projects related to Tensaku, grouped by what they do, with what Tensaku takes from each. Checked
2026-11-07. The Herb and Rails background, and discussion threads, are in [RESEARCH.md](RESEARCH.md).

✅ take · 🔧 take with changes · ❌ leave out · 👀 watch

## Foundation

| Project | What it is | For Tensaku |
|---|---|---|
| [Herb](https://github.com/marcoroth/herb) | HTML-aware ERB parser and engine. Rails 8.2 (unreleased) uses its engine for HTML templates. | ✅ Required. Parsing for splices, `SourceAttributionVisitor` for element positions ([docs](https://github.com/marcoroth/herb/blob/main/docs/docs/projects/engine/visitors/source-attribution.md)). |
| [Herb Dev Tools](https://herb-tools.dev/projects/dev-tools) | In-browser outlines, "Open in Editor", diagnostics panel | ✅ Reuse "Open in Editor" when installed, don't rebuild it. 👀 Could grow toward editing. |
| [Herb Dev Server](https://github.com/marcoroth/herb/pull/1662) | Pushes template changes to the open page, keeping focus and caret | 🔧 Use for the page update after a save when it's running (needs ReActionView's slots feature). |
| [ReActionView](https://github.com/marcoroth/reactionview) | Herb template handler for Rails 8.1, reactive ERB templates, ships the dev tools and dev server | ✅ Required, development only. Provides the Herb engine on Rails 8.1 and the hook for Tensaku's visitor. |
| [idiomorph](https://github.com/bigskysoftware/idiomorph) | DOM morphing, used by Turbo 8 | ✅ Bundled for refetch-and-morph after a save. |

## Click to source

Click an element on the page to find or open the code that rendered it.

| Project | Stack | How it finds the source | For Tensaku |
|---|---|---|---|
| [Herb Dev Tools](https://herb-tools.dev/projects/dev-tools) | Rails (Herb) | `data-herb-debug-*` and `data-herb-source` attributes | ✅ Same stamps. |
| [rails-template-inspector](https://github.com/aki77/rails-template-inspector) | Rails | Rails' filename comments (`annotate_rendered_view_with_filenames`), file only | ❌ File-level only. |
| [xray-rails](https://github.com/brentd/xray-rails) | Rails | Injected template boundary markers | ❌ Unmaintained, file-level. |
| [LocatorJS](https://github.com/infi-pc/locatorjs) | React, Vue, Svelte, Solid, Preact | React DevTools hook, or ids added at compile time | 🔧 UX reference: hover highlight, Alt-click. |
| [React Grab](https://github.com/aidenybai/react-grab) | React | Component stack with `file:line:col`; hover and Cmd+C copies it | 🔧 "Copy reference" interaction. |
| [click-to-component](https://github.com/ericclemmons/click-to-component) | React | React's `_debugSource` (removed in React 19) | ❌ Shows why runtime-only mapping breaks. |
| [code-inspector-plugin](https://github.com/zh-lx/code-inspector) | Many (Vite, webpack) | `data-insp-path` added at compile time | — Same model as Herb's stamps. |
| [vite-plugin-vue-inspector](https://github.com/webfansplz/vite-plugin-vue-inspector) | Vue | `data-v-inspector` added at compile time | — Same model. |
| [vite-plugin-svelte inspector](https://github.com/sveltejs/vite-plugin-svelte) | Svelte | `__svelte_meta` in dev builds | — Same model. |
| [Astro dev toolbar](https://github.com/withastro/astro) | Astro | `data-astro-source-file` / `data-astro-source-loc` in development | 🔧 Toolbar UX reference. |

## Agent toolbars and notes

Point at something on the page, write what should change, and an agent gets the context.

| Project | Stack | How it works | License | For Tensaku |
|---|---|---|---|---|
| [Agentation](https://github.com/benjitaylor/agentation) + `agentation-mcp` | React | Click, select text or drag an area, write a note. MCP: pending notes, resolve, watch; the agent can acknowledge or ask a question. | PolyForm Shield (no competing products, so no forking) | 🔧 Note model and MCP tools (`watch`, question status). Code not reused. |
| [agentation-rails](https://github.com/yakschuss/agentation-rails) | Rails | Agentation port injected by Rack. Selectors, partial paths from Rails' filename comments, Stimulus controllers. Copy as Markdown. | PolyForm Shield | 🔧 Proof that Rack injection works. Stimulus and Turbo Frame context in references. |
| [agentation gem](https://github.com/c-sonnier/agentation_gem) | Rails | Ruby port of the toolbar, selectors only | — | ❌ |
| [Tidewave](https://tidewave.ai) | Rails, Phoenix, JS | Browser toolbar: click adds an element to the prompt for Tidewave's own agent, Ctrl-click opens the template. [tidewave_rails](https://github.com/tidewave-ai/tidewave_rails) is an MCP server (eval, logs, SQL, docs, source locations). | Toolbar paid, MCP gem Apache-2.0 | 🔧 Safety model (dev only, local only, error outside reloading environments). The MCP gem works next to Tensaku. |
| [Vibe Annotations](https://github.com/RaphaelRegnier/vibe-annotations) | Any (Chrome extension) | Notes on localhost pages, local MCP server, "watch mode" loop | PolyForm Shield | 🔧 Watch loop. |
| [ui-annotator-mcp](https://github.com/mcpware/ui-annotator-mcp) | Any | Reverse proxy injects an annotation script, MCP tools to read elements | MIT | — |
| [Pinagent](https://github.com/Pinagent/pinagent) | Vite, Next | Comment on an element, the agent gets `file:line` and a screenshot | Apache-2.0 | — |
| Pinpoint ([Cursor forum](https://forum.cursor.com/t/pinpoint-click-the-element-say-what-should-change-and-cursor-gets-the-context/173643)) | Any (extension) | Selector, styles, component chain, a cropped screenshot, MCP | — | — Several products share the name. |
| [Pointa](https://www.pointa.dev/), [annotaKit](https://github.com/nodestarQ/annotaKit) | Any, Svelte | Similar point-and-annotate tools | — | — |
| [Stagewise](https://github.com/stagewise-io/stagewise) | Any | Started as a toolbar sending element context to Cursor or Windsurf, now its own IDE | AGPL-3.0 | ❌ |
| [Windsurf Previews](https://docs.windsurf.com/windsurf/previews), [Codex browser](https://developers.openai.com/codex/app/browser), [Cursor Design Mode](https://cursor.com/changelog/3-0) | Any | Select or comment on elements inside the agent's own browser | Paid | 👀 Where the big tools are going. |

## Editing in the page, written back to source

| Project | Stack | How it works | For Tensaku |
|---|---|---|---|
| [Onlook](https://github.com/onlook-dev/onlook) | React, Next, Tailwind | Visual editor that writes changes to code. Elements carry a `data-oid` ([LogRocket](https://blog.logrocket.com/onlook-react-visual-editor)). | 🔧 Proof that attribute-based write-back works. Much bigger scope (layout, styles). |
| [TinaCMS](https://tina.io/docs/contextual-editing/tinafield) | React, Markdown/JSON in git | `data-tina-field` on rendered elements, a click opens the field | 🔧 Explicit attribute for cases the automatic mapping misses (`data-tensaku-group`). |
| [Sanity Presentation](https://www.sanity.io/docs/visual-editing/stega) | Any frontend, Sanity content | Source location hidden in each string as zero-width characters ("stega"). `stegaClean` before comparing values. | 🔧 Idea for translation markers. Tensaku uses the simpler i18n_proofreading markers. |
| [Vercel Content Link](https://payloadcms.com/docs/integrations/vercel-content-link) | Any, CMS content | Same stega technique. `data-vercel-edit-target` widens a highlight. | 🔧 Highlight grouping. |
| [Builder.io Projects](https://builder.io/c/docs/projects-local-repo) | React | Visual editor on a local repo, AI applies the change | ❌ Paid, AI regenerates instead of splicing. |
| [v0 Design Mode](https://community.vercel.com/t/edit-ui-with-v0s-design-mode/17477) | v0 projects | Edit text and styles, the agent regenerates code | ❌ Same. |

## Translations in the page

| Project | How it works | For Tensaku |
|---|---|---|
| [i18n_proofreading](https://github.com/yshmarov/i18n_proofreading) | The I18n backend appends a hidden `⟦key⟧` marker when a cookie is set. The widget strips the markers and remembers which key produced each text. Suggestions only. Active, Rails 7.1–8.1. | ✅ The marker technique, including its rules (no `number.*`/`date.*`, no keyless `default:`). |
| [i18n-edit](https://github.com/BrucePerens/i18n-edit) | Patches `I18n.translate` to emit a `contenteditable` span, writes the YAML. 2017, dead. | ❌ Loses YAML comments on save: the failure Tensaku's splice avoids. |
| [rails-i18n-onair](https://github.com/tarqmamdouh/rails-i18n-onair) | Dashboard plus inline "Live UI" editing, YAML or Postgres | — |
| [i18n_viz](https://github.com/railslove/i18n_viz), [iye](https://github.com/relatel/iye) | Show keys next to text, YAML editor. Old. | — |

## Rails agent tooling (works next to Tensaku)

| Project | What it is |
|---|---|
| [tidewave_rails](https://github.com/tidewave-ai/tidewave_rails) | MCP server for a running Rails app: eval, logs, SQL, docs, source locations |
| [rails-mcp-server](https://github.com/maquina-app/rails-mcp-server) | MCP server for Rails projects |
| [rails-ai-context](https://github.com/crisnahine/rails-ai-context) | Rails context for agents |
| [herb#1755 Herb MCP proposal](https://github.com/marcoroth/herb/issues/1755) | Proposed static-analysis MCP tools for ERB (render graph, partial interfaces). Not accepted yet. |
