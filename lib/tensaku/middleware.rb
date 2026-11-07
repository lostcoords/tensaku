module Tensaku
  # Development only. Serves the overlay and the endpoints under Tensaku.config.mount_path, and adds
  # the overlay to HTML pages: a meta tag with the request method and the boot token in <head>, and the
  # script before </body>.
  #
  # The overlay goes only into HTML pages requested from this machine with a local Host (see
  # Guard.local_request?), with a 2xx status or 422 (a form shown again with its errors). A page is a
  # whole document, or a fragment the browser opens as a page or frame (a mailer preview part).
  # Fragments fetched by scripts (htmx, Stimulus) and pages requested through another host name get
  # no token. Translation markers are stripped from every other text response.
  class Middleware
    HTML = %r{\Atext/html}
    STRIP_TYPES = %r{\A(?:text/|application/(?:json|xml|javascript|ld\+json))}
    SCRIPT_OR_STYLE = %r{(<(script|style)\b[^>]*>)(.*?)(</\2>)}im
    DOCUMENT = %r{<html[\s>]|</head>|</body>}i
    NONCE = "action_dispatch.content_security_policy_nonce"
    PAGE_DESTINATIONS = %w[document iframe frame].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      return Endpoints.new.call(env) if env["PATH_INFO"].to_s.start_with?("#{Tensaku.config.mount_path}/")

      status, headers, body = @app.call(env)
      return [ status, headers, body ] if passthrough?(status, headers, body, env)

      type = headers["content-type"].to_s
      if type.match?(HTML)
        overlay = ((200..299).cover?(status) || status == 422) && Guard.local_request?(Rack::Request.new(env))
        rewrite(status, headers, body) do |html|
          page = html.match?(DOCUMENT) || PAGE_DESTINATIONS.include?(env["HTTP_SEC_FETCH_DEST"])
          overlay && page ? inject(html, env) : strip_document(html, fragment: !page)
        end
      elsif type.match?(STRIP_TYPES) && !type.include?("event-stream")
        rewrite(status, headers, body) { I18nMarkers.strip(it) }
      else
        [ status, headers, body ]
      end
    end

    private

    # Responses left as they are: empty ones, downloads, files served from disk, streams and
    # compressed bodies.
    def passthrough?(status, headers, body, env)
      status == 204 || status == 304 ||
        headers["content-disposition"].to_s.start_with?("attachment") ||
        headers["content-encoding"] ||
        headers["x-accel-buffering"] == "no" ||
        body.respond_to?(:to_path) ||
        live?(env)
    end

    def live?(env)
      controller = env["action_controller.instance"]
      defined?(ActionController::Live) && controller.is_a?(ActionController::Live)
    end

    def rewrite(status, headers, body)
      html = +""
      body.each { html << it }
      body.close if body.respond_to?(:close)
      html.force_encoding(Encoding::UTF_8)
      return [ status, headers, [ html ] ] unless html.valid_encoding?

      html = yield(html)
      headers = headers.dup
      headers.delete("content-length")
      headers.delete("etag")
      [ status, headers, [ html ] ]
    end

    # An HTML fragment (htmx, a Stimulus fetch) keeps its markers for the overlay on the page that
    # inserts it. A whole document that gets no overlay loses them.
    def strip_document(html, fragment:)
      fragment ? html : I18nMarkers.strip(html)
    end

    def inject(html, env)
      # Markers inside scripts and styles would end up in code; the overlay can't reach those.
      html = html.gsub(SCRIPT_OR_STYLE) { "#{$1}#{I18nMarkers.strip($3)}#{$4}" } if html.include?(I18nMarkers::FENCE)
      return html if html.include?("data-tensaku-request=")

      root = "#{env["SCRIPT_NAME"]}#{Tensaku.config.mount_path}"
      nonce = env[NONCE].presence
      meta = %(<meta name="tensaku" data-tensaku-request="#{ERB::Util.h(env["REQUEST_METHOD"])}" data-tensaku-token="#{Tensaku.token}" data-tensaku-root="#{ERB::Util.h(root)}" data-tensaku-shortcut="#{ERB::Util.h(Tensaku.config.shortcut)}">)
      script = %(<script src="#{ERB::Util.h(root)}/tensaku.js?v=#{Endpoints.asset_digest}"#{%( nonce="#{ERB::Util.h(nonce)}") if nonce} data-turbo-eval="false" data-tensaku-ui defer></script>)

      html = insert_before(html, "</head>", meta) || "#{meta}#{html}"
      insert_before(html, "</body>", script) || "#{html}#{script}"
    end

    def insert_before(html, tag, snippet)
      index = html.rindex(/#{Regexp.escape(tag)}/i)
      return nil unless index

      html.dup.insert(index, snippet)
    end
  end
end
