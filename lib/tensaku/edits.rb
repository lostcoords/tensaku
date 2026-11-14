module Tensaku
  # Notices an agent's edits to the app's files, so the page can show each one as it lands instead of
  # waiting for the agent to resolve its note. The dev server only looks while a note is being worked
  # on (Notes.working?), and then compares a stamp of the files under DIRS a few times a second.
  # Builds of a CSS or JS watcher land in app/assets/builds, so they count as edits too.
  module Edits
    DIRS = %w[app config/locales].freeze

    # Several open tabs share one look at the files.
    FRESH = 0.2
    LOCK = Mutex.new

    module_function

    # The number of files and the sum of their modification times: a change to any file, or a file
    # added or deleted, changes it.
    def stamp(root = Tensaku.root)
      LOCK.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return @stamp if @stamp && @root == root && now - @at < FRESH

        files = DIRS.flat_map { Dir.glob(File.join(root.to_s, it, "**", "*")) }
        newest = files.sum(0.0) { File.mtime(it).to_f rescue 0.0 }
        @root = root
        @at = now
        @stamp = [ files.size, newest ]
      end
    end
  end
end
