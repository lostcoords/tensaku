require "socket"
require "digest"
require "tmpdir"
require "securerandom"

module Tensaku
  # Wakes the processes waiting for an app's notes to change, so none of them polls. A waiting reader
  # (a page's event stream in the dev server, a watch_notes call) listens on a Unix socket of its own
  # in the app's folder; a writer, once its change is committed, connects to each socket there and
  # sends a byte. A socket that refuses the connection belongs to a process that is gone, and is
  # deleted.
  #
  # The sockets live under /tmp (Dir.tmpdir on Windows), in a folder only this user can open, because
  # a socket path is limited to about 100 bytes. Where Unix sockets aren't available, a reader checks
  # once a second instead.
  module Doorbell
    # How long a reader without a socket sleeps between checks.
    FALLBACK = 1.0

    module_function

    def dir(root)
      base = Gem.win_platform? ? Dir.tmpdir : "/tmp"
      Pathname(base).join("tensaku-#{Process.uid}", Digest::SHA256.hexdigest(Pathname(root).expand_path.to_s)[0, 12])
    end

    def ring(root)
      folder = dir(root)
      return unless folder.directory?

      folder.glob("*.sock").each do |path|
        UNIXSocket.open(path.to_s) { it.write_nonblock("!", exception: false) }
      rescue Errno::ECONNREFUSED, Errno::ENOENT, Errno::ENOTSOCK
        path.delete rescue nil
      rescue SystemCallError, IOError
        nil
      end
    rescue NotImplementedError, SystemCallError
      nil
    end

    # A reader's socket, for one or more apps.
    class Listener
      def initialize(roots)
        @servers = Array(roots).filter_map do |root|
          folder = Doorbell.dir(root)
          folder.mkpath
          folder.parent.chmod(0o700)
          path = folder.join("#{Process.pid}-#{SecureRandom.hex(3)}.sock")
          [ UNIXServer.new(path.to_s), path ]
        rescue NotImplementedError, SystemCallError, NameError
          nil
        end
      end

      # Waits until a writer rings or timeout seconds pass. True when rung.
      def wait(timeout)
        if @servers.empty?
          sleep [ timeout, FALLBACK ].min
          return true
        end
        ready, = IO.select(@servers.map(&:first), nil, nil, timeout)
        return false unless ready

        ready.each do |server|
          while (client = server.accept_nonblock(exception: false)).is_a?(UNIXSocket)
            client.close
          end
        end
        true
      end

      def close
        @servers.each do |server, path|
          server.close
          path.delete if path.exist?
        rescue SystemCallError, IOError
          nil
        end
        @servers = []
      end
    end

    def listen(roots)
      listener = Listener.new(roots)
      yield listener
    ensure
      listener&.close
    end
  end
end
