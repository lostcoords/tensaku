# Installation

Tensaku needs Ruby 4.0 or later and Rails 8.1 or later. Add it to the development group only:

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
- Makes sure `tmp/` is ignored by git.

It prints every file it changes.

## JavaScript

No JavaScript setup is needed. Tensaku's middleware injects one prebuilt script into HTML pages in development. It works with importmap, jsbundling or no JavaScript at all.

## Check that it works

Start the server and open a page. A small round button with 添 sits in the bottom right corner. Hover an element in select mode (Alt+Shift+T) and the label shows the file and line it came from.
