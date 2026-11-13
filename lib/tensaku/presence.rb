require "monitor"

module Tensaku
  # Whether an agent session's process is still running. A running session holds an exclusive lock on
  # a file named after it in Tensaku.home/sessions, and the operating system drops the lock when the
  # process ends, however it ends. Unlike a process id, which the system can give to a new process
  # after a crash, a dropped lock can't come back.
  module Presence
    HELD = {}
    LOCK = Monitor.new

    module_function

    def dir
      Tensaku.home.join("sessions")
    end

    def path(session)
      dir.join("#{session}.lock")
    end

    # Takes the lock for session in this process, once.
    def hold(session)
      LOCK.synchronize do
        key = path(session).to_s
        return if HELD[key]

        dir.mkpath
        file = File.open(key, File::RDWR | File::CREAT, 0o600)
        file.flock(File::LOCK_EX)
        HELD[key] = file
      end
    end

    def release(session)
      LOCK.synchronize do
        file = HELD.delete(path(session).to_s)
        next unless file

        File.delete(file.path) if File.exist?(file.path)
        file.close
      end
    end

    # A session held in this process is alive. Otherwise it is alive while another process holds its
    # lock; a lock file nobody holds is left by a process that ended, and is deleted.
    def alive?(session)
      key = path(session).to_s
      return true if LOCK.synchronize { HELD.key?(key) }

      File.open(key, File::RDWR) do |file|
        free = file.flock(File::LOCK_EX | File::LOCK_NB)
        File.delete(key) if free
        !free
      end
    rescue Errno::ENOENT
      false
    end
  end
end
