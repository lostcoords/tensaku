# Tensaku

Tensaku (添削, correcting a draft) lets you fix a running Rails app from the page itself, in development. Click a piece of text and edit it in place, and Tensaku writes the change back to the ERB template, the locale YAML or the Markdown source. Or leave a note on an element or an area of the page, and your coding agent reads it with the exact file and line attached.

Tensaku is built on [Herb](https://github.com/marcoroth/herb) through [ReActionView](https://github.com/marcoroth/reactionview), and only runs in development. Production doesn't change: it keeps rendering with Erubi and never loads Tensaku, ReActionView or Herb.

Status: 0.0.1, unreleased. Requires Ruby 4.0+ and Rails 8.1+.

## Two things it does

**Edit text in place.** Alt-click a heading, a button label or a paragraph. The editor shows the source, not the rendered text: in `Hello <%= user.name %>!` you edit `Hello ` and `!`, and the Ruby stays as a locked chip. Enter saves. Tensaku replaces exactly those bytes in the file and updates the page without a reload.

**Leave notes for an agent.** Click an element, or drag over an area, and write what should change. The note is saved with the file and line of every element it points at. Your coding agent reads it through MCP, the note files, the clipboard or a Claude Code skill, makes the change and resolves the note. You see the pin turn green.

## Try it here

This site is a Rails app, and Tensaku runs on it in development. Clone the repository, run `bin/rails server` in `docs/`, and every paragraph on these pages can be edited. They are Markdown files rendered by Kiln.

## Where to start

- [Installation](/installation): add the gem and run the generator.
- [Editing text](/editing): what can be edited and how a save works.
- [Notes](/notes) and [Notes for agents](/agents): the note workflow.
- [Safety and limits](/safety): what Tensaku never does.
