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

    # What the overlay last selected, for the MCP `current_selection` tool. One person, one browser.
    def self.selection
      @selection
    end

    def self.selection=(value)
      @selection = value
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
    rescue Error, JSON::ParserError => error
      json({ error: error.message }, 422)
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
        template, line, column = Source::Template.from_stamp(params["stamp"])
        edits = Array(params["edits"]).map { it.to_h.symbolize_keys }
        written(template.edit_text(line, column, edits), :template)
      in [ "POST", "/attribute" ]
        template, line, column = Source::Template.from_stamp(params["stamp"])
        written(template.edit_attribute(line, column, params["name"].to_s, params.to_h.symbolize_keys), :template)
      in [ "GET", "/translation" ]
        json(key: params["key"], locales: Source::Locale.lookup_all(params["key"].to_s))
      in [ "POST", "/translation" ]
        result = Source::Locale.edit(params["locale"].to_s, params["key"].to_s, original: params["original"], text: params["text"])
        written(result, :locale)
      in [ "GET", "/markdown" ]
        json(Source::Markdown.new(params["range"]).describe(tag: params["tag"]))
      in [ "POST", "/markdown" ]
        written(Source::Markdown.new(params["range"]).edit(original: params["original"], text: params["text"]), :markdown)
      in [ "GET", "/notes" ]
        Notes.prune!
        json(notes: Notes.list(url: params["url"].presence, status: params["status"].presence), open: Notes.list(status: %w[open question]).size)
      in [ "GET", "/notes.md" ]
        notes = params["id"].present? ? [ Notes.find(params["id"]) ] : Notes.list(url: params["url"].presence, status: params["status"].presence || %w[open question])
        [ 200, { "content-type" => "text/markdown; charset=utf-8" }, [ Notes.to_markdown(notes) ] ]
      in [ "POST", "/notes" ]
        json(Notes.create(params), 201)
      in [ "PATCH", %r{\A/notes/([a-z0-9]+)\z} ]
        id = path.split("/").last
        json(Notes.update(id, status: params["status"], reply: params["reply"], comment: params["comment"]))
      in [ "DELETE", %r{\A/notes/([a-z0-9]+)\z} ]
        Notes.delete(path.split("/").last)
        json({ deleted: true })
      in [ "POST", "/selection" ]
        self.class.selection = params.to_h.slice("url", "targets", "text").merge("at" => Time.now.utc.iso8601)
        json({ ok: true })
      else
        json({ error: "Not found" }, 404)
      end
    end

    def written(result, kind)
      Caches.clear!(kind) if result[:changed]
      json(result.merge(warning: Caches.fragment_cache_warning).compact)
    end

    def script(request)
      raise Forbidden, "Tensaku only answers requests from this machine" unless Guard.loopback?(request)

      [ 200, { "content-type" => "text/javascript; charset=utf-8", "cache-control" => "no-cache" }, [ File.read(ASSET) ] ]
    end

    def body(request)
      raw = request.body&.read.to_s
      raw.empty? ? {} : JSON.parse(raw)
    end

    def json(data, status = 200)
      [ status, { "content-type" => "application/json; charset=utf-8", "cache-control" => "no-store" }, [ JSON.generate(data) ] ]
    end
  end
end
