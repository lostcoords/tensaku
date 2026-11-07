# Configuration

Tensaku works without configuration. To change a default, add an initializer and guard it, because Tensaku is only loaded in development:

```ruby
# config/initializers/tensaku.rb
if defined?(Tensaku)
  Tensaku.configure do |config|
    config.writable_paths << "content"
    config.shortcut = "alt+shift+KeyT"
    config.prune_after = 7 * 24 * 60 * 60
  end
end
```

| Option | Default | |
|---|---|---|
| `writable_paths` | `app/views`, `app/components`, `config/locales` | Directories Tensaku may write to, relative to the app root |
| `shortcut` | `"alt+shift+KeyT"` | Modifiers and a `KeyboardEvent#code` for select mode |
| `prune_after` | 3 days | Seconds before resolved notes are deleted |
| `notes_path` | `tmp/tensaku/notes` | Where note files are written |

Other gems can call `Tensaku.register_writable_path("their/dir")`.
