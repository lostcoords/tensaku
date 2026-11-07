module Tensaku
  module Source
    # Markdown blocks, addressed by the ranges a producer writes:
    # data-tensaku-md="path:startLine:startCol-endLine:endCol", 1-based lines and byte columns, end
    # column inclusive (commonmarker's sourcepos). Tensaku doesn't render Markdown; it replaces text
    # inside a block's range and leaves the rest of the file alone.
    class Markdown
      EXTENSIONS = %w[.md .markdown].freeze

      # Block syntax at the start of a range that stays locked: heading hashes, list markers, quotes.
      PREFIX = /\A(?:\#{1,6}[ \t]+|[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d{1,9}[.)][ \t]+|>[ \t]?)/

      # Block tags whose text is edited; others (tables, code) only get notes. A whole list is edited
      # as its source, markers included.
      EDITABLE = %w[p h1 h2 h3 h4 h5 h6 li blockquote ul ol].freeze
      WHOLE = %w[ul ol].freeze

      def self.parse_range(value)
        match = value.to_s.match(/\A(?<path>.+):(?<sl>\d+):(?<sc>\d+)-(?<el>\d+):(?<ec>\d+)\z/)
        raise Error, "Not a Markdown range: #{value.inspect}" unless match

        [ match[:path], *%i[sl sc el ec].map { match[it].to_i } ]
      end

      attr_reader :relative_path

      def initialize(range)
        @relative_path, @start_line, @start_column, @end_line, @end_column = self.class.parse_range(range)
        @path = Guard.writable_file!(@relative_path, extensions: EXTENSIONS)
        @source = File.read(@path, mode: "rb").force_encoding(Encoding::UTF_8)
      end

      def describe(tag: nil)
        raw = block_source
        prefix = WHOLE.include?(tag.to_s.downcase) ? "" : raw[PREFIX].to_s
        {
          file: relative_path,
          range: "#{@start_line}:#{@start_column}-#{@end_line}:#{@end_column}",
          editable: tag.nil? || EDITABLE.include?(tag.to_s.downcase),
          prefix:,
          text: raw.delete_prefix(prefix),
          original: raw
        }
      end

      # original: the block's whole source when the editor opened. text: the new source after the
      # locked prefix.
      def edit(original:, text:, tag: nil)
        @source = File.read(@path, mode: "rb").force_encoding(Encoding::UTF_8)
        raw = block_source
        raise StaleSource, "#{relative_path} changed since the page was rendered. Reload the page and try again." unless raw == original.to_s

        prefix = WHOLE.include?(tag.to_s.downcase) ? "" : raw[PREFIX].to_s
        replacement = prefix + text.to_s.tr(" ", " ").delete("\r")
        return { changed: false, file: relative_path } if replacement == raw

        start, finish = byte_range
        FileWrite.atomic(@path, FileWrite.splice(@source, [ { start:, end: finish, text: replacement } ]))
        { changed: true, file: relative_path }
      end

      private

      def block_source
        start, finish = byte_range
        @source.byteslice(start...finish).force_encoding(Encoding::UTF_8)
      end

      def byte_range
        lines = @source.b.lines
        raise StaleSource, "#{relative_path} is shorter than the page says. Reload the page." if @end_line > lines.size

        offset = ->(line) { lines.first(line - 1).sum(&:bytesize) }
        start = offset.call(@start_line) + @start_column - 1
        last_line = lines[@end_line - 1].chomp
        finish = offset.call(@end_line) + [ @end_column, last_line.bytesize ].min
        [ start, finish ]
      end
    end
  end
end
