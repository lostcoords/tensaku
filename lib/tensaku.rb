require "securerandom"
require "tensaku/version"

# Tensaku edits text on a running Rails page and writes it back to the source, and keeps notes for
# coding agents. It does nothing outside development (see Tensaku.enabled?).
module Tensaku
  # Loaded on first use, so an app that lists Tensaku in the wrong Gemfile group loads none of it
  # (nor Herb) outside development.
  autoload :Guard, "tensaku/guard"
  autoload :FileWrite, "tensaku/file_write"
  autoload :Middleware, "tensaku/middleware"
  autoload :Endpoints, "tensaku/endpoints"
  autoload :Notes, "tensaku/notes"
  autoload :Mcp, "tensaku/mcp"
  autoload :Caches, "tensaku/caches"
  autoload :I18nMarkers, "tensaku/i18n"

  module Source
    autoload :HtmlText, "tensaku/source/html_text"
    autoload :Template, "tensaku/source/template"
    autoload :Locale, "tensaku/source/locale"
    autoload :Markdown, "tensaku/source/markdown"
  end

  class Error < StandardError; end

  # A write that would change the wrong bytes: the file changed since the page rendered, or the target
  # moved. Nothing is merged or guessed.
  class StaleSource < Error; end

  # A request the guard refuses: not loopback, wrong token, or a path outside the allow-list.
  class Forbidden < Error; end

  class Config
    # Directories, relative to Rails.root, that Tensaku may write to.
    attr_reader :writable_paths

    # Where note files live, relative to Rails.root.
    attr_accessor :notes_path

    # Resolved notes older than this are deleted.
    attr_accessor :prune_after

    # Keyboard shortcut that toggles the overlay, as modifier keys and a KeyboardEvent#code.
    attr_accessor :shortcut

    # Where the middleware serves the overlay and the endpoints.
    attr_accessor :mount_path

    def initialize
      @writable_paths = %w[app/views app/components config/locales]
      @notes_path = "tmp/tensaku/notes"
      @prune_after = 3 * 24 * 60 * 60
      @shortcut = "alt+shift+KeyT"
      @mount_path = "/__tensaku"
    end
  end

  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield config
    end

    # Lets another gem allow writes to its own source directory, for example Kiln's content/.
    def register_writable_path(path)
      config.writable_paths << path.to_s unless config.writable_paths.include?(path.to_s)
    end

    def enabled?
      defined?(Rails) && Rails.env.development?
    end

    # A per-boot secret embedded in the page. Write requests must echo it back.
    def token
      @token ||= SecureRandom.hex(16)
    end

    # The app root that relative source paths resolve against. Tests point it at a scratch copy.
    attr_writer :root

    def root
      Pathname(@root || Rails.root)
    end
  end
end

require "tensaku/railtie" if defined?(Rails::Railtie)
