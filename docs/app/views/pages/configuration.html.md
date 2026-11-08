# Configuration

Tensaku works without configuration. To change a default, add an initializer and guard it with the environment, because Tensaku is only loaded in development. `defined?(Tensaku)` is not enough: with a path gem, Bundler loads `Tensaku::VERSION` in every environment.

```ruby
# config/initializers/tensaku.rb
if Rails.env.development?
  Tensaku.configure do |config|
    config.writable_paths << "content"
    config.shortcut = "alt+shift+KeyT"
    config.prune_after = 7 * 24 * 60 * 60
  end
end
```

| Option | Default | |
|---|---|---|
| `writable_paths` | `app/views`, `app/components`, `config/locales` | Directories and single files Tensaku may write to, relative to the app root |
| `shortcut` | `"alt+shift+KeyT"` | Modifiers and a `KeyboardEvent#code` for select mode |
| `prune_after` | 3 days | Seconds before resolved notes are deleted |
| `notes_path` | `tmp/tensaku/notes` | Where note files are written |

A file in `writable_paths` allows only that file, so a Markdown file outside the app, such as `../CONTRIBUTING.md`, can be edited without opening its whole directory.

Other gems can call `Tensaku.register_writable_path("their/dir")`.
