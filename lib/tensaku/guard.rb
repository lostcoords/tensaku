require "ipaddr"

module Tensaku
  # Every endpoint goes through here: requests from this machine only, the boot token for anything
  # that reads source or writes, and writes limited to the allow-list.
  #
  # "From this machine" means a loopback peer address, no proxy header naming another client, a Host
  # that is a local name (or one the app lists in config.hosts), and no Origin from another site. The
  # Host check stops DNS rebinding: a page on another domain that resolves to 127.0.0.1.
  module Guard
    LOOPBACK = [ IPAddr.new("127.0.0.0/8"), IPAddr.new("::1/128") ].freeze
    FORWARDED = %w[HTTP_X_FORWARDED_FOR HTTP_X_REAL_IP HTTP_FORWARDED HTTP_CLIENT_IP HTTP_TRUE_CLIENT_IP HTTP_CF_CONNECTING_IP].freeze

    module_function

    def loopback?(request)
      loopback_address?(request.get_header("REMOTE_ADDR")) && !forwarded_from_elsewhere?(request)
    end

    # Whether the request came from this machine and from a page of this app, not another site.
    def local_request?(request)
      return false unless loopback?(request)

      origin = request.get_header("HTTP_ORIGIN")
      return false if origin && !local_url?(origin)

      allowed_host?(raw_host(request))
    end

    def check_request!(request)
      check_local_client!(request)

      token = request.get_header("HTTP_X_TENSAKU_TOKEN").to_s
      raise Forbidden, "Missing or wrong Tensaku token. Reload the page." unless secure_compare(token, Tensaku.token)
    end

    # The MCP endpoint can't use the page token (its clients never see the page), so it relies on this
    # check alone. Every other endpoint adds the token on top.
    def check_local_client!(request)
      raise Forbidden, "Tensaku only answers requests from this machine" unless loopback?(request)

      origin = request.get_header("HTTP_ORIGIN")
      raise Forbidden, "Cross-origin requests are refused" if origin && !local_url?(origin)
      raise Forbidden, "Unexpected Host header" unless allowed_host?(raw_host(request))
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

    def loopback_address?(address)
      ip = IPAddr.new(address.to_s)
      LOOPBACK.any? { it.include?(ip) }
    rescue IPAddr::InvalidAddressError
      false
    end

    # A proxy in front of the app (a tunnel, nginx) connects from 127.0.0.1 and names the real client
    # in a header. Any client named there that isn't loopback means the request came from elsewhere.
    def forwarded_from_elsewhere?(request)
      FORWARDED.any? do |name|
        value = request.get_header(name).to_s
        next false if value.empty?

        addresses = name == "HTTP_FORWARDED" ? value.scan(/for="?\[?([^\]";,\s]+)/i).flatten : value.split(",")
        addresses.empty? || addresses.any? { !loopback_address?(it.strip.sub(/:\d+\z/, "")) }
      end
    end

    # The Host header as sent, not request.host, which trusts X-Forwarded-Host.
    def raw_host(request)
      host = request.get_header("HTTP_HOST").to_s
      host.start_with?("[") ? host[/\A\[[^\]]*\]/].to_s : host.sub(/:\d+\z/, "")
    end

    def local_url?(url)
      allowed_host?(URI.parse(url).host.to_s)
    rescue URI::InvalidURIError
      false
    end

    def allowed_host?(host)
      local_host?(host) || app_host?(host)
    end

    def local_host?(host)
      host = host.to_s.delete_prefix("[").delete_suffix("]").downcase
      host == "localhost" || host.end_with?(".localhost") || (IPAddr.new(host).loopback? rescue false)
    end

    # A name the app allows in config.hosts (for example a puma-dev .test domain). An empty list allows
    # every host in Rails; here it allows none beyond the local names. IP ranges in the list don't count:
    # Rails' development default allows every IP.
    def app_host?(host)
      return false if host.to_s.empty? || !defined?(Rails) || !Rails.application

      hosts = Array(Rails.application.config.hosts).reject { it.is_a?(IPAddr) }
      hosts.any? && ActionDispatch::HostAuthorization::Permissions.new(hosts).allows?(host)
    rescue StandardError
      false
    end
  end
end
