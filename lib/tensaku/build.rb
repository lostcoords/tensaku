require "digest"

module Tensaku
  # A fingerprint of Tensaku's Ruby code. Each process takes it when it starts (Build.started); comparing
  # it with the code on disk now (Build.current) tells a dev server or an agent's `tensaku mcp` that
  # runs older code than the overlay script, which the page loads fresh on every request. A released
  # gem's files don't change, so there the two differ only after an upgrade.
  module Build
    FILES = File.expand_path("../**/*.rb", __dir__)
    LOCK = Mutex.new

    module_function

    def started
      @started ||= current
    end

    # Hashes the files again only when one of them changed since the last call.
    def current
      LOCK.synchronize do
        stamp = Dir[FILES].sort.map { [ it, File.mtime(it).to_f, File.size(it) ] }
        @current = nil unless @stamp == stamp
        @stamp = stamp
        @current ||= Digest::SHA256.hexdigest(stamp.map { |path, *| File.binread(path) }.join("\0"))[0, 12]
      end
    end

    def stale?
      started != current
    end
  end
end
