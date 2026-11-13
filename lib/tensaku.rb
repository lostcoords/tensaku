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
  autoload :Agents, "tensaku/agents"
  autoload :Project, "tensaku/project"
  autoload :Session, "tensaku/session"
  autoload :Store, "tensaku/store"
  autoload :Repo, "tensaku/repo"
  autoload :Doorbell, "tensaku/doorbell"
  autoload :Presence, "tensaku/presence"
  autoload :Build, "tensaku/build"
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
    # Directories and files, relative to Rails.root, that Tensaku may write to.
    attr_reader :writable_paths

    # Resolved and declined notes older than this move to the archive.
    attr_accessor :archive_after

    # Where the middleware serves the overlay and the endpoints.
    attr_accessor :mount_path

    def initialize
      @writable_paths = %w[app/views app/components config/locales]
      @archive_after = 3 * 24 * 60 * 60
      @mount_path = "/__tensaku"
    end
  end

  TOKEN_LOCK = Mutex.new
  TOKEN = /\A\h{32}\z/

  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield config
    end

    # Lets another gem allow writes to its own source directory or file.
    def register_writable_path(path)
      config.writable_paths << path.to_s unless config.writable_paths.include?(path.to_s)
    end

    def enabled?
      defined?(Rails) && Rails.env.development?
    end

    # A secret embedded in the page. Write requests must echo it back. It lives in tmp/tensaku/token,
    # so every Puma worker and the next server boot use the same one (a page stays valid across a
    # restart). Deleting the file makes a new one.
    def token
      @token || TOKEN_LOCK.synchronize { @token ||= read_or_create_token }
    end

    def token_path
      Pathname(Rails.root).join("tmp/tensaku/token")
    end

    # The app root that relative source paths resolve against. Tests point it at a scratch copy.
    # `tensaku mcp` runs without Rails and sets it per app with with_root.
    attr_writer :root

    def root
      Pathname(Thread.current[:tensaku_root] || @root || Rails.root)
    end

    # The folder for Tensaku's database, shared by every app and checkout on this machine: TENSAKU_HOME,
    # else the platform's per-user data folder.
    def home
      return Pathname(ENV["TENSAKU_HOME"]) unless ENV["TENSAKU_HOME"].to_s.empty?

      if Gem.win_platform?
        Pathname(ENV["LOCALAPPDATA"].to_s.empty? ? File.join(Dir.home, "AppData", "Local") : ENV["LOCALAPPDATA"]).join("tensaku")
      elsif RUBY_PLATFORM.include?("darwin")
        Pathname(Dir.home).join("Library", "Application Support", "tensaku")
      else
        Pathname(ENV["XDG_DATA_HOME"].to_s.empty? ? File.join(Dir.home, ".local", "share") : ENV["XDG_DATA_HOME"]).join("tensaku")
      end
    end

    # Runs the block with root set to path, in this thread only.
    def with_root(path)
      previous = Thread.current[:tensaku_root]
      Thread.current[:tensaku_root] = Pathname(path)
      yield
    ensure
      Thread.current[:tensaku_root] = previous
    end

    private

    def read_or_create_token
      path = token_path
      path.dirname.mkpath
      existing = path.file? ? path.read.strip : ""
      return existing if existing.match?(TOKEN)

      path.delete if path.file?
      # Written to a temp file and linked into place, so a worker never reads a half-written token,
      # and the first worker to link wins.
      temp = path.dirname.join(".token-#{SecureRandom.hex(4)}")
      temp.write(SecureRandom.hex(16))
      temp.chmod(0o600)
      begin
        File.link(temp, path)
      rescue Errno::EEXIST
        nil
      ensure
        temp.delete
      end
      path.read.strip.then { it.match?(TOKEN) ? it : SecureRandom.hex(16) }
    rescue SystemCallError
      SecureRandom.hex(16)
    end
  end
end

require "tensaku/railtie" if defined?(Rails::Railtie)
