<h1 align="center">Tensaku</h1>

<p align="center">
  <img src="https://img.shields.io/badge/status-experimental-e8b44f" alt="Status: experimental">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Rails-8.1-b45d3c?logo=rubyonrails&amp;logoColor=white" alt="Rails 8.1"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-57966f" alt="License: MIT"></a>
</p>

<p align="center">
  Fix your Rails app on the page, in development.
</p>

<p align="center">
  <a href="https://tensaku.lostcoords.com">Documentation</a> ·
  <a href="https://tensaku.lostcoords.com/installation">Installation</a> ·
  <a href="https://tensaku.lostcoords.com/safety">Safety and limits</a>
</p>

Tensaku (添削, correcting a draft) lets you click text on a running Rails page and edit it. It writes the change back to the ERB template, the locale YAML or the Markdown file. For anything that isn't a text edit, leave a note on the page, and your coding agent reads it with the file and line of each element.

Tensaku is experimental. It needs Ruby 4.0 or later and Rails 8.1. It runs only in development, on [Herb](https://github.com/marcoroth/herb) through [ReActionView](https://github.com/marcoroth/reactionview). Test and production keep rendering with Erubi and never load Tensaku, ReActionView or Herb.

## Install it in a Rails app

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

The generator writes `config/initializers/reactionview.rb`, installs a Claude Code skill in `.claude/skills/tensaku/` and adds the MCP endpoint to `.mcp.json`. It prints every file it changes. You don't set up any JavaScript. The middleware injects one prebuilt script into HTML pages.

Start the server and open a page. A round 添 button sits in the bottom right corner. Press **Alt+Shift+T** to select an element and see the file and line it came from.

## Edit text where you see it

Alt-click (Option-click) any text. The editor shows the source, so in `Hello <%= user.name %>!` you edit `Hello ` and `!` and the Ruby stays a locked chip. Enter saves, Escape cancels, and a toast offers Undo.

Tensaku edits static template text, attributes such as `alt` and `placeholder`, `t()` translations in every locale, and Markdown blocks. Each save replaces only the bytes of the edited text, and refuses if the file changed since the page rendered. The page then updates in place, with no reload.

## Leave notes for your agent

In select mode, click an element, select some text, or drag over an area, and choose **Add note**. Notes are JSON files in `tmp/tensaku/notes/`, ignored by git. Your agent reads them from the files, from the MCP endpoint at `/__tensaku/mcp`, through the Claude Code skill, or from Markdown you copy from the page.

The agent marks a note `working`, asks a question back, or resolves it with a reply. Each change shows on the note's pin. A green pin means the change is ready for you to check.

## Documentation

The documentation site is [tensaku.lostcoords.com](https://tensaku.lostcoords.com). Its pages are Markdown files in `docs/app/views/pages/`.

- [Install Tensaku](docs/app/views/pages/installation.html.md) and see [what the generator does](docs/app/views/pages/installation.html.md#what-the-generator-does).
- Read [what can be edited](docs/app/views/pages/editing.html.md) and [how a save works](docs/app/views/pages/editing.html.md#how-a-save-works).
- Leave [notes](docs/app/views/pages/notes.html.md), and give agents the [note format and MCP tools](docs/app/views/pages/agents.html.md).
- Look up the [configuration options](docs/app/views/pages/configuration.html.md) and the [attributes the overlay reads](docs/app/views/pages/producers.html.md).
- Read [safety and limits](docs/app/views/pages/safety.html.md) before you use it on a real app.
- [Contribute](CONTRIBUTING.md) or read the [changelog](CHANGELOG.md).

## License

Tensaku is licensed under the [MIT License](LICENSE).
