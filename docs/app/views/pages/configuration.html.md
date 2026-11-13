# Configuration

Tensaku works without configuration.

After reading this page, you will know:

- How to change a default.
- Every option and what it does.
- Which settings live outside the initializer.

## Change a default

Add an initializer and guard it with the environment, because Tensaku is only loaded in development:

```ruby
# config/initializers/tensaku.rb
if Rails.env.development?
  Tensaku.configure do |config|
    config.writable_paths << "content"
    config.archive_after = 7 * 24 * 60 * 60
  end
end
```

Use `Rails.env.development?` rather than `defined?(Tensaku)`. With a path gem, Bundler loads `Tensaku::VERSION` in every environment.

## Options

| Option | Default | Does |
|---|---|---|
| `writable_paths` | `app/views`, `app/components`, `config/locales` | Directories and single files Tensaku may write to, relative to the app root |
| `archive_after` | 3 days | Seconds before resolved and declined notes move to the archive |
| `mount_path` | `/__tensaku` | Where the overlay and the endpoints are served. `tensaku mcp` doesn't use it. |

A file in `writable_paths` allows only that file, so a Markdown file outside the app, such as `../CONTRIBUTING.md`, can be edited without opening its whole directory.

Other gems can call `Tensaku.register_writable_path("their/dir")`.

## Other settings

- **Open in editor** uses the editor named by `RAILS_EDITOR` or `EDITOR`.
- **ReActionView** can be adjusted in `config/initializers/reactionview.rb`, which runs after Tensaku sets it up.
- **Overlay preferences** are kept in the browser. See [settings](/notes/#settings).

## Where notes are kept

Notes are in `tensaku.sqlite3` in your user data folder (see [where notes live](/notes/#where-notes-live)). Set the `TENSAKU_HOME` environment variable to keep them in another folder, for the dev server and for `tensaku mcp` alike.
