require "json"
require "digest"

module Tensaku
  # The JSON endpoints the overlay talks to, plus the overlay script. Everything needs a loopback
  # address, and everything except the script needs the boot token. Agents don't come through here:
  # `tensaku mcp` works on the database directly.
  class Endpoints
    ASSET = File.expand_path("../../app/assets/tensaku.js", __dir__)

    # Edit mode asks about every stamp on the page at once.
    EDITABLE_LIMIT = 5000

    # An event stream waits on the doorbell, and checks anyway this often: for an agent that stopped
    # checking in, and to write a comment so a closed tab is noticed.
    STREAM_CHECK = 10

    # While an agent works on a note, the stream also looks at the app's files this often (Edits).
    EDIT_CHECK = 0.25

    # /notes/ID and /notes/ID/screenshot.
    NOTE_PATH = %r{\A/notes/([a-z0-9]+)(?:/screenshot)?\z}

    def self.asset_digest
      Digest::SHA256.file(ASSET).hexdigest[0, 12]
    rescue Errno::ENOENT
      "missing"
    end

    def call(env)
      request = Rack::Request.new(env)
      path = request.path_info.delete_prefix(Tensaku.config.mount_path)

      return script(request) if path == "/tensaku.js" && request.get?

      Guard.check_request!(request)
      route(request, path)
    rescue Forbidden => error
      json({ error: error.message }, 403)
    rescue StaleSource => error
      json({ error: error.message, stale: true }, 409)
    rescue Notes::NotFound => error
      json({ error: error.message }, 404)
    rescue Error, JSON::ParserError, ArgumentError, TypeError => error
      json({ error: error.message }, 422)
    rescue StandardError => error
      # Tensaku sits in front of Rails' exception pages, so it logs and answers for itself.
      Rails.logger.error("[Tensaku] #{error.class}: #{error.message}\n#{Array(error.backtrace).first(10).join("\n")}")
      json({ error: "Tensaku hit an error: #{error.class}: #{error.message}. The server log has the details." }, 500)
    end

    private

    def route(request, path)
      params = request.get? ? request.GET : body(request)
      note_id = path[NOTE_PATH, 1]

      case [ request.request_method, path ]
      in [ "GET", "/source" ]
        template, line, column = Source::Template.from_stamp(params["stamp"])
        json(template.describe(line, column))
      in [ "POST", "/editable" ]
        stamps = Array(params["stamps"]).map(&:to_s).uniq
        raise Error, "Too many stamps (#{stamps.size}); the limit is #{EDITABLE_LIMIT}" if stamps.size > EDITABLE_LIMIT
        json(editable: Source::Template.editable(stamps))
      in [ "POST", "/text" ]
        edits = Array(params["edits"]).map { object!(it, "An edit").symbolize_keys }
        written(:template) do
          template, line, column = Source::Template.from_stamp(params["stamp"])
          template.edit_text(line, column, edits)
        end
      in [ "POST", "/attribute" ]
        written(:template) do
          template, line, column = Source::Template.from_stamp(params["stamp"])
          template.edit_attribute(line, column, params["name"].to_s, params.to_h.symbolize_keys)
        end
      in [ "GET", "/translation" ]
        json(key: params["key"], locales: Source::Locale.lookup_all(params["key"].to_s))
      in [ "POST", "/translation" ]
        written(:locale) { Source::Locale.edit(params["locale"].to_s, params["key"].to_s, original: params["original"], text: params["text"]) }
      in [ "GET", "/markdown" ]
        json(Source::Markdown.new(params["range"]).describe(tag: params["tag"]))
      in [ "POST", "/markdown" ]
        written(:markdown) { Source::Markdown.new(params["range"]).edit(original: params["original"], text: params["text"], tag: params["tag"]) }
      in [ "GET", "/notes" ]
        visited(request)
        # restart: Tensaku's code changed since this server started, so it answers with the old code
        # while the page runs the new overlay script.
        # archived=1 lists the archive instead, for the notes panel's Archive tab.
        listed = Notes.list(url: params["url"].presence, status: ("archived" if params["archived"] == "1"))
        # changed_at: the last time an agent said something on a note in this app, so the page fetches
        # itself again to show its change, whatever page the note was on.
        json(notes: listed, open: Notes.active_count, agents: Agents.list, restart: Build.stale?, changed_at: Notes.last_agent_message_at)
      in [ "GET", "/events" ]
        events(request)
      in [ "GET", "/notes.md" ]
        notes = Notes.list(url: params["url"].presence, status: Notes::ACTIVE)
        markdown = params["format"] == "short" ? Notes::Markdown.short(notes) : Notes::Markdown.list(notes)
        [ 200, { "content-type" => "text/markdown; charset=utf-8" }, [ markdown ] ]
      in [ "POST", "/notes" ]
        json(Notes.create(params), 201)
      in [ "PUT", %r{\A/notes/[a-z0-9]+/screenshot\z} ]
        json(Notes.attach_screenshot(note_id, params["png"]))
      in [ "GET", %r{\A/notes/[a-z0-9]+/screenshot\z} ]
        shot = Notes.screenshot(note_id) or raise Notes::NotFound, "That note has no screenshot"
        [ 200, { "content-type" => "image/png", "cache-control" => "no-store" }, [ shot["png"] ] ]
      in [ "PATCH", %r{\A/notes/[a-z0-9]+\z} ]
        # An edit or a message is for the agent: the note is sent again. A status change alone (done,
        # reopened, or undoing either) isn't.
        changed = params["message"].present? || params["comment"].present?
        json(Notes.update(note_id, status: params["status"], comment: params["comment"],
          message: params["message"], from: "you", send: changed && params["status"] == "open", to: params["to"]))
      in [ "POST", "/notes/archive" ]
        json(archived: Notes.archive!(params["ids"]))
      in [ "DELETE", %r{\A/notes/[a-z0-9]+\z} ]
        Notes.delete(note_id)
        json({ deleted: true })
      in [ "GET", "/editor" ]
        json(url: editor_url(params["file"], params["line"]))
      in [ "POST", "/selection" ]
        Project.select!(params.to_h.slice("url", "targets", "text"), tab: params["tab"])
        json({ ok: true })
      else
        json({ error: "Not found" }, 404)
      end
    end

    # Server-sent events: a "changed" event whenever the notes or the agents change (Project.version),
    # and one right away, so the page loads the notes when told instead of asking every few seconds.
    # While an agent works on a note, an "edited" event whenever the app's files change (Edits), so the
    # page shows each edit as it lands. The stream sleeps on the doorbell until a write rings it.
    # The connection is taken over from the web server (Rack hijack) and served from a thread of its
    # own, so an open tab doesn't hold one of the server's threads. A server without hijack answers
    # 501, and the page polls instead.
    def events(request)
      hijack = request.env["rack.hijack"]
      return json({ error: "This web server can't stream events" }, 501) unless hijack

      visited(request)
      io = hijack.call
      root = Tensaku.root
      Thread.new { Tensaku.with_root(root) { stream(io) } }
      [ -1, {}, [] ]
    end

    def stream(io)
      Doorbell.listen(Tensaku.root) do |doorbell|
        io.write("HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\ncache-control: no-store\r\nconnection: close\r\n\r\n")
        last = files = nil
        quiet = 0.0
        loop do
          version = Project.version
          stamp = Edits.stamp if Notes.working?
          events = []
          events << "data: changed\n\n" if version != last
          events << "data: edited\n\n" if stamp && files && stamp != files
          # A comment now and then, so a closed tab is noticed.
          events << ": ping\n\n" if events.empty? && quiet >= STREAM_CHECK
          if events.any?
            io.write(events.join)
            io.flush
            quiet = 0.0
          end
          last, files = version, stamp
          wait = stamp ? EDIT_CHECK : STREAM_CHECK
          quiet += wait unless doorbell.wait(wait)
        end
      end
    rescue IOError, SystemCallError
      nil # the tab closed
    ensure
      io.close unless io.closed?
    end

    # The page asks for its notes: archive the old ones, and keep the URL agents' links start with.
    def visited(request)
      Notes.prune!
      Project.base_url = request.base_url
    end

    # A link that opens the file in the editor named by RAILS_EDITOR or EDITOR, through Rails' own
    # list of editors, or nil when none is set.
    def editor_url(file, line)
      editor = ActiveSupport::Editor.current
      return nil unless editor

      path = Tensaku.root.join(file.to_s).expand_path
      raise Error, "Not a file in this app: #{file}" unless path.to_s.start_with?(Tensaku.root.expand_path.to_s + "/") && path.file?

      editor.url_for(path.to_s, line.to_i.clamp(1, 1_000_000))
    end

    # Reads, checks and writes the source under the write lock.
    def written(kind)
      result = FileWrite.locked { yield }
      Caches.clear!(kind) if result[:changed]
      json(result.merge(warning: Caches.fragment_cache_warning).compact)
    end

    def script(request)
      raise Forbidden, "Tensaku only answers requests from this machine" unless Guard.loopback?(request)

      [ 200, { "content-type" => "text/javascript; charset=utf-8", "cache-control" => "no-cache" }, [ File.read(ASSET) ] ]
    end

    def body(request)
      raw = request.body&.read.to_s
      raw.empty? ? {} : object!(JSON.parse(raw), "The request body")
    end

    def object!(value, what)
      raise Error, "#{what} must be a JSON object" unless value.is_a?(Hash)

      value
    end

    def json(data, status = 200)
      [ status, { "content-type" => "application/json; charset=utf-8", "cache-control" => "no-store" }, [ JSON.generate(data) ] ]
    end
  end
end
