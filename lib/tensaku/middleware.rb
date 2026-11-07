module Tensaku
  # Development only. Serves the overlay and the endpoints under Tensaku.config.mount_path, and adds
  # the overlay to HTML pages: a meta tag with the request method and the boot token in <head>, and the
  # script before </body>.
  class Middleware
    HTML = %r{\Atext/html}
    STRIP_TYPES = %r{\A(?:text/|application/(?:json|xml|javascript|ld\+json))}
    SCRIPT_OR_STYLE = %r{(<(script|style)\b[^>]*>)(.*?)(</\2>)}im

    def initialize(app)
      @app = app
    end

    def call(env)
      return Endpoints.new.call(env) if env["PATH_INFO"].to_s.start_with?("#{Tensaku.config.mount_path}/")

      status, headers, body = @app.call(env)
      type = headers["content-type"].to_s
      return [ status, headers, body ] if status == 204 || status == 304 || headers["content-disposition"].to_s.start_with?("attachment")

      if type.match?(HTML) && !headers["content-encoding"]
        rewrite(status, headers, body) { inject(it, env) }
      elsif type.match?(STRIP_TYPES) && !headers["content-encoding"] && !type.include?("event-stream")
        rewrite(status, headers, body) { I18nMarkers.strip(it) }
      else
        [ status, headers, body ]
      end
    end

    private

    def rewrite(status, headers, body)
      html = +""
      body.each { html << it }
      body.close if body.respond_to?(:close)
      html = yield(html.force_encoding(Encoding::UTF_8))
      headers = headers.dup
      headers.delete("content-length")
      headers.delete("etag")
      [ status, headers, [ html ] ]
    end

    def inject(html, env)
      # Markers inside scripts and styles would end up in code; the overlay can't reach those.
      html = html.gsub(SCRIPT_OR_STYLE) { "#{$1}#{I18nMarkers.strip($3)}#{$4}" } if html.include?(I18nMarkers::FENCE)
      return html if html.include?("data-tensaku-request=")

      meta = %(<meta name="tensaku" data-tensaku-request="#{ERB::Util.h(env["REQUEST_METHOD"])}" data-tensaku-token="#{Tensaku.token}" data-tensaku-root="#{ERB::Util.h(Tensaku.config.mount_path)}" data-tensaku-shortcut="#{ERB::Util.h(Tensaku.config.shortcut)}">)
      script = %(<script src="#{Tensaku.config.mount_path}/tensaku.js?v=#{Endpoints.asset_digest}" data-turbo-eval="false" data-tensaku-ui defer></script>)

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
