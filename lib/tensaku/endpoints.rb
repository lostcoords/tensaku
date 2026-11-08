require "json"
require "digest"

module Tensaku
  # The JSON endpoints the overlay talks to, plus the overlay script and the MCP endpoint. Everything
  # except the script needs a loopback address, and everything the overlay calls needs the boot token.
  class Endpoints
    ASSET = File.expand_path("../../app/assets/tensaku.js", __dir__)

    # Edit mode asks about every stamp on the page at once.
    EDITABLE_LIMIT = 5000

    def self.asset_digest
      Digest::SHA256.file(ASSET).hexdigest[0, 12]
    rescue Errno::ENOENT
      "missing"
    end

    def call(env)
      request = Rack::Request.new(env)
      path = request.path_info.delete_prefix(Tensaku.config.mount_path)

      return script(request) if path == "/tensaku.js" && request.get?

      if path == "/mcp"
        Guard.check_local_client!(request)
        return Mcp.new.call(request)
      end

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
        Notes.prune!
        json(notes: Notes.list(url: params["url"].presence), open: Notes.list(status: Notes::ACTIVE).size, agent: Notes.agent)
      in [ "GET", "/notes.md" ]
        notes = params["id"].present? ? [ Notes.find(params["id"]) ] : Notes.list(url: params["url"].presence, status: Notes::ACTIVE)
        markdown = params["format"] == "short" ? Notes.to_short_markdown(notes) : Notes.to_markdown(notes)
        [ 200, { "content-type" => "text/markdown; charset=utf-8" }, [ markdown ] ]
      in [ "POST", "/notes" ]
        json(Notes.create(params), 201)
      in [ "PATCH", %r{\A/notes/([a-z0-9]+)\z} ]
        id = path.split("/").last
        json(Notes.update(id, status: params["status"], reply: params["reply"], comment: params["comment"],
          message: params["message"], from: "you", targets: params["targets"]))
      in [ "DELETE", %r{\A/notes/([a-z0-9]+)\z} ]
        Notes.delete(path.split("/").last)
        json({ deleted: true })
      in [ "GET", "/editor" ]
        json(url: editor_url(params["file"], params["line"]))
      in [ "POST", "/selection" ]
        Notes.selection = params.to_h.slice("url", "targets", "text").merge("at" => Time.now.utc.iso8601)
        json({ ok: true })
      else
        json({ error: "Not found" }, 404)
      end
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
