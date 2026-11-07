# Installation

Tensaku needs Ruby 4.0 or later and Rails 8.1. Rails 8.2 isn't supported yet. Add the gem to the development group only:

```ruby
# Gemfile
group :development do
  gem "tensaku"
end
```

Then install it and run the generator:

```sh
bundle install
bin/rails generate tensaku:install
```

## What the generator does

- Checks that Tensaku is in the development group, and warns if it isn't.
- Writes `config/initializers/reactionview.rb`, guarded by `defined?(ReActionView)`.
- Installs the Claude Code skill in `.claude/skills/tensaku/`.
- Adds the MCP endpoint to `.mcp.json`. Pass `--port` if your server doesn't run on 3000.
- Adds `/tmp/tensaku/` to `.gitignore` unless `tmp/` is already ignored, so notes stay local.

It prints every file it changes.

## JavaScript

You don't set up any JavaScript. Tensaku's middleware injects one prebuilt script into HTML pages in development. It works with importmap, jsbundling or no JavaScript at all.

## Check that it works

Start the server and open a page. A round 添 button sits in the bottom right corner. Press Alt+Shift+T for select mode and hover an element. The label shows the file and line it came from.
