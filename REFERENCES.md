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
This shortlist includes permissively licensed implementation references. Licenses and
documented features were checked on 2026-11-07; these tools have not been tested locally.
The borrowing suggestions are proposals for Tensaku.

| Project | Stack | How it works | License | For Tensaku |
|---|---|---|---|---|
| [Pinagent](https://github.com/Pinagent/pinagent) | React, Vue, and Svelte through Vite, Next.js, Nuxt, and SvelteKit; also React Native and Expo | Tags web elements with source positions. Captures comments with `file:line` and screenshots, stores them in local SQLite, and exposes a feedback queue over MCP. | [Apache-2.0](https://github.com/Pinagent/pinagent/blob/main/LICENSE) for `packages/`, `apps/cli/`, and `examples/` | 🔧 First reference for source-aware feedback records, persistence, screenshots, and resolution. Use the local packages as the implementation reference. |
| [AnnotaKit](https://github.com/nodestarQ/annotaKit) | Svelte 5 | Floating toolbar, element and text selection, multi-select, comments, animation freeze, component context, Markdown export, and an MCP bridge. Agents can acknowledge, reply, resolve, dismiss, and watch. | [MIT](https://github.com/nodestarQ/annotaKit/blob/main/LICENSE) | 🔧 First reference for the annotation interaction: select, comment, preview, edit, and resolve. Also study its compact and detailed export formats. |
| [Pointa](https://github.com/AmElmo/pointa) ([website](https://www.pointa.dev/)) | Framework-independent Chrome extension for localhost | Captures annotations, element structure, styles, screenshots, and bug timelines. An MCP server gives agents access to the feedback. Its design mode previews visual changes for an agent to apply. | [MIT](https://github.com/AmElmo/pointa/blob/main/LICENSE) | 🔧 Context capture and batch review. Keep feedback capture separate from applying an edit to source. |
| [UI Annotator MCP](https://github.com/mcpware/ui-annotator-mcp) | Framework-independent reverse proxy | Injects hover labels into a page and exposes element inspection through MCP without a browser extension. | [MIT](https://github.com/mcpware/ui-annotator-mcp/blob/main/LICENSE) | 🔧 Lightweight element identification and inspection. Useful context alongside source locations. |

For fast source capture, also study [React Grab](https://github.com/aidenybai/react-grab)
and its [MIT license](https://github.com/aidenybai/react-grab/blob/main/LICENSE).
Hover an element, press Cmd+C or Ctrl+C, and paste its element and component source
context into an agent. Its selection primitives cover hit testing, source context,
page freezing, clipboard access, and editor navigation. This is a reference for a
low-friction "copy reference" action.

For Vue, Svelte, React, Astro, Solid, and other source inspectors, study
[Code Inspector](https://github.com/zh-lx/code-inspector)
([MIT](https://github.com/zh-lx/code-inspector/blob/main/LICENSE)) and
[LocatorJS](https://github.com/infi-pc/locatorjs)
([MIT](https://github.com/infi-pc/locatorjs/blob/master/LICENSE)). Both connect a
rendered element to its source. Borrow hover outlines, keyboard activation, and
editor navigation, while retaining Herb's source stamps in Tensaku.

## Editing in the page, written back to source

| Project | Stack | How it works | License | For Tensaku |
|---|---|---|---|---|
| [Onlook](https://github.com/onlook-dev/onlook) | Open-source edition focuses on Next.js and Tailwind | Instruments code to map rendered elements to source. Previews visual edits in an iframe and applies them to code. Includes element selection, layout and style editing, code navigation, and checkpoints. | [Apache-2.0](https://github.com/onlook-dev/onlook/blob/main/LICENSE.md) | 🔧 First reference for selection, edit feedback, preview, and undo. Adapt the interaction to Tensaku's byte splices rather than adopting its full editor scope. |
| [TinaCMS](https://tina.io/docs/contextual-editing/tinafield) ([source](https://github.com/tinacms/tinacms)) | React, Markdown and JSON content | `data-tina-field` maps rendered content to an editable field in a sidebar. | [Apache-2.0](https://github.com/tinacms/tinacms/blob/main/LICENSE) | 🔧 Clear "this text belongs to this field" feedback and explicit grouping when automatic source mapping is insufficient. |
| [Sanity Visual Editing](https://github.com/sanity-io/visual-editing) | React, Vue, Svelte, Astro, and vanilla JavaScript | Clickable preview overlays navigate to a document and field. Includes a standalone build for non-React environments. | [MIT](https://github.com/sanity-io/visual-editing/blob/main/LICENSE) | 🔧 Overlay placement and field targeting. Its [stega technique](https://www.sanity.io/docs/visual-editing/stega) is background for translation markers; Tensaku uses the simpler i18n_proofreading markers. |

Start with Pinagent for source-aware feedback, AnnotaKit for annotation interactions,
React Grab for quick capture, and Onlook for direct-editing feedback. Keep Tensaku's
template, translation, and Markdown writes deterministic and limited to their source pieces.

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
| [tidewave_rails](https://github.com/tidewave-ai/tidewave_rails) | [Apache-2.0](https://github.com/tidewave-ai/tidewave_rails/blob/main/LICENSE) MCP server for a running Rails app: eval, logs, SQL, docs, source locations. Study the open-source server's development-only integration and runtime context. |
| [rails-mcp-server](https://github.com/maquina-app/rails-mcp-server) | MCP server for Rails projects |
| [rails-ai-context](https://github.com/crisnahine/rails-ai-context) | Rails context for agents |
| [herb#1755 Herb MCP proposal](https://github.com/marcoroth/herb/issues/1755) | Proposed static-analysis MCP tools for ERB (render graph, partial interfaces). Not accepted yet. |
