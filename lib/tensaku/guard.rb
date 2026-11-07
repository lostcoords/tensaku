require "ipaddr"

module Tensaku
  # Every endpoint goes through here: loopback addresses only, the boot token for anything that reads
  # source or writes, and writes limited to the allow-list.
  module Guard
    LOOPBACK = [ IPAddr.new("127.0.0.0/8"), IPAddr.new("::1/128") ].freeze

    module_function

    def loopback?(request)
      address = request.get_header("REMOTE_ADDR").to_s
      LOOPBACK.any? { it.include?(IPAddr.new(address)) }
    rescue IPAddr::InvalidAddressError
      false
    end

    def check_request!(request)
      raise Forbidden, "Tensaku only answers requests from this machine" unless loopback?(request)

      token = request.get_header("HTTP_X_TENSAKU_TOKEN").to_s
      raise Forbidden, "Missing or wrong Tensaku token. Reload the page." unless secure_compare(token, Tensaku.token)
    end

    # MCP clients can't read the page token, so the MCP endpoint relies on loopback plus a check that
    # the request doesn't come from a web page (no foreign Origin, a local Host).
    def check_local_client!(request)
      raise Forbidden, "Tensaku only answers requests from this machine" unless loopback?(request)

      origin = request.get_header("HTTP_ORIGIN")
      raise Forbidden, "Cross-origin requests are refused" if origin && !local_url?(origin)

      host = request.host.to_s
      raise Forbidden, "Unexpected Host header" unless local_host?(host)
    end

    # Resolves a path from the page (relative to Rails.root) to a real file inside the allow-list.
    def writable_file!(relative, extensions:)
      raise Forbidden, "No file given" if relative.to_s.empty?

      path = Tensaku.root.join(relative.to_s)
      raise Forbidden, "#{relative} does not exist" unless path.file?

      real = path.realpath
      inside = writable_dirs.any? { real.to_s.start_with?("#{it}/") }
      raise Forbidden, "#{relative} is outside Tensaku's writable paths (#{Tensaku.config.writable_paths.join(", ")})" unless inside

      unless extensions.any? { real.basename.to_s.end_with?(it) }
        raise Forbidden, "#{relative} is not a #{extensions.join(" or ")} file"
      end

      real
    end

    # The configured paths, plus Kiln's content directory when Kiln's content layer is loaded.
    def writable_dirs
      dirs = Tensaku.config.writable_paths.map { Tensaku.root.join(it) }
      dirs << Pathname(Kiln::Content.root) if defined?(::Kiln::Content) && ::Kiln::Content.respond_to?(:root)
      dirs.select(&:directory?).map(&:realpath)
    end

    def secure_compare(a, b)
      a.bytesize == b.bytesize && OpenSSL.fixed_length_secure_compare(a, b)
    end

    def local_url?(url)
      local_host?(URI.parse(url).host.to_s)
    rescue URI::InvalidURIError
      false
    end

    def local_host?(host)
      host = host.delete_prefix("[").delete_suffix("]")
      host == "localhost" || host.end_with?(".localhost") || (IPAddr.new(host).loopback? rescue false)
    end
  end
end
