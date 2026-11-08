# Tensaku

Tensaku (添削, correcting a draft) lets you click text on a running Rails page and edit it. It writes the change back to the ERB template, the locale YAML or the Markdown file. For anything that isn't a text edit, leave a note on the page, and your coding agent reads it with the file and line of each element.

Tensaku runs only in development, on [Herb](https://github.com/marcoroth/herb) through [ReActionView](https://github.com/marcoroth/reactionview). Test and production keep rendering with Erubi and never load Tensaku, ReActionView or Herb.

Tensaku is experimental. Version 0.0.1 on RubyGems reserves the name, and nothing is stable yet. It needs Ruby 4.0 or later and Rails 8.1.

## Edit text, or leave a note

**Edit text in place.** Alt-click a heading, a button label or a paragraph. The editor shows the source, not the rendered text. In `Hello <%= user.name %>!` you edit `Hello ` and `!`, and the Ruby stays a locked chip. Enter saves. Tensaku replaces exactly those bytes in the file and updates the page without a reload.

**Leave notes for an agent.** Click an element, or drag over an area, and write what should change. The note is saved with the file and line of every element it points at. Your coding agent reads it through MCP, the note files, the clipboard or a Claude Code skill, makes the change and resolves the note. You see the pin turn green.

## Try it here

This site is a Rails app, and Tensaku runs on it in development. Clone the repository and run `bin/rails server` in `docs/`. You can then edit every paragraph on these pages. They are Markdown files that Kiln renders.

## Where to start

- [Install Tensaku](/installation/) with the gem and the generator.
- Read [what can be edited](/editing/) and how a save works.
- Leave [notes](/notes/), and give your agent the [note format and MCP tools](/agents/).
- Read [safety and limits](/safety/) before you use it on a real app.
