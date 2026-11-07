module Tensaku
  module FileWrite
    module_function

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
  end
end
