module Tensaku
  module FileWrite
    module_function

    # Runs the block holding one lock shared by every thread and every process (the dev server and
    # `tensaku mcp`), so two saves can't both read a file, check it and then overwrite each other's change. Writers re-read the file
    # inside the block. Nested calls in the same thread don't wait on themselves.
    def locked
      return yield if Thread.current[:tensaku_write_lock]

      path = Tensaku.root.join("tmp/tensaku/write.lock")
      path.dirname.mkpath
      File.open(path, File::RDWR | File::CREAT, 0o644) do |file|
        file.flock(File::LOCK_EX)
        begin
          Thread.current[:tensaku_write_lock] = true
          yield
        ensure
          Thread.current[:tensaku_write_lock] = nil
        end
      end
    end

    # Writes through a temp file in the same directory and renames it over the original, keeping the
    # file mode, so a crash can't leave half a file behind.
    def atomic(path, content)
      path = Pathname(path)
      temp = path.dirname.join(".#{path.basename}.tensaku-#{SecureRandom.hex(4)}")
      File.open(temp, File::WRONLY | File::CREAT | File::EXCL, path.stat.mode) do |file|
        file.binmode
        file.write(content)
        file.fsync
      end
      File.rename(temp, path)
    ensure
      File.unlink(temp) if temp && File.exist?(temp)
    end

    # Replaces byte ranges in a string. Ranges must not overlap; they're applied back to front so the
    # earlier offsets stay valid.
    def splice(source, replacements)
      result = source.b
      replacements.sort_by { -it[:start] }.each_cons(2) do |later, earlier|
        raise ArgumentError, "overlapping replacements" if earlier[:end] > later[:start]
      end
      replacements.sort_by { -it[:start] }.each do |replacement|
        result[replacement[:start]...replacement[:end]] = replacement[:text].b
      end
      result.force_encoding(source.encoding)
    end

    # The lines a write changed, for the overlay's save message: the first line's number, then the old
    # and new lines between what the two versions share at each end.
    def diff(before, after)
      was, now = [ before, after ].map { it.dup.force_encoding(Encoding::UTF_8).scrub.lines(chomp: true) }
      prefix = 0
      prefix += 1 while prefix < was.size && prefix < now.size && was[prefix] == now[prefix]
      suffix = 0
      suffix += 1 while suffix < was.size - prefix && suffix < now.size - prefix && was[-1 - suffix] == now[-1 - suffix]
      { line: prefix + 1, removed: was[prefix...(was.size - suffix)], added: now[prefix...(now.size - suffix)] }
    end
  end
end
