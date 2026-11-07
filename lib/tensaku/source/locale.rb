require "psych"

module Tensaku
  module Source
    # Locale YAML, edited without load-and-dump: Psych's parse tree gives each scalar's position, and
    # only the value's bytes change. Comments, ordering and quoting stay as they were. Every write is
    # checked by loading the result and comparing the edited value before the file is replaced.
    module Locale
      EXTENSIONS = %w[.yml .yaml].freeze
      INTERPOLATION = /%\{[^}]+\}/

      Entry = Data.define(:file, :path, :source, :node, :value) do
        def line = node.start_line + 1

        def to_h
          { file:, line:, value:, style: Locale.style_name(node.style), editable: true }
        end
      end

      module_function

      # The file that defines locale.key, the last one in I18n.load_path order (the one that wins).
      # Only files inside Tensaku's writable paths count.
      def find(locale, key)
        candidates(locale).reverse_each do |relative, path|
          source = File.read(path, mode: "rb").force_encoding(Encoding::UTF_8)
          node = scalar_at(Psych.parse(source), [ locale.to_s, *key.to_s.split(".") ])
          return Entry.new(relative, path, source, node, node.value) if node
        rescue Psych::SyntaxError
          next
        end
        nil
      end

      # Every available locale's entry for the key, for the other-locales view.
      def lookup_all(key)
        I18n.available_locales.to_h do |locale|
          entry = find(locale, key)
          [ locale.to_s, entry&.to_h || { value: I18n.t(key, locale:, default: nil)&.then { it.is_a?(String) ? it : nil }, editable: false } ]
        end
      end

      # Replaces the value of locale.key. `original` is the value the page was rendered with.
      def edit(locale, key, original:, text:)
        text = text.to_s.delete("\r")
        entry = find(locale, key) or raise Error, "#{locale}.#{key} isn't defined in a writable locale file"
        raise StaleSource, "#{entry.file} changed since the page was rendered. Reload the page and try again." unless entry.value == original.to_s

        if text.scan(INTERPOLATION).sort != entry.value.scan(INTERPOLATION).sort
          raise Error, "Keep the same %{...} placeholders: #{entry.value.scan(INTERPOLATION).join(", ")}"
        end
        return { changed: false, file: entry.file } if text == entry.value

        start, finish = byte_range(entry.source, entry.node)
        replacement = render(entry, text, entry.source.byteslice(start...finish))
        updated = FileWrite.splice(entry.source, [ { start:, end: finish, text: replacement } ])

        check!(updated, locale, key, text, entry.file)
        FileWrite.atomic(entry.path, updated)
        { changed: true, file: entry.file, line: entry.line }
      end

      def style_name(style)
        { Psych::Nodes::Scalar::PLAIN => "plain", Psych::Nodes::Scalar::SINGLE_QUOTED => "single",
          Psych::Nodes::Scalar::DOUBLE_QUOTED => "double", Psych::Nodes::Scalar::LITERAL => "literal",
          Psych::Nodes::Scalar::FOLDED => "folded" }.fetch(style, "plain")
      end

      def candidates(locale)
        allowed = Guard.writable_dirs.map(&:to_s)
        root = Tensaku.root.realpath
        I18n.load_path.flatten.filter_map do |entry|
          path = Pathname(entry.to_s).expand_path
          next unless EXTENSIONS.include?(path.extname) && path.file?

          path = path.realpath
          next unless allowed.any? { path.to_s.start_with?("#{it}/") }

          [ path.relative_path_from(root).to_s, path ]
        end.uniq.select { |_, path| File.read(path).include?(locale.to_s) }
      end

      def scalar_at(document, keys)
        node = document&.root
        keys.each do |key|
          return nil unless node.is_a?(Psych::Nodes::Mapping)

          pair = node.children.each_slice(2).to_a.reverse.find { |name, _| name.is_a?(Psych::Nodes::Scalar) && name.value == key }
          return nil unless pair

          node = pair.last
        end
        node if node.is_a?(Psych::Nodes::Scalar)
      end

      # Psych positions are 0-based lines and character columns.
      def byte_range(source, node)
        lines = source.lines
        offset = ->(line, column) { lines.first(line).sum(&:bytesize) + lines.fetch(line, "")[0, column].to_s.bytesize }
        [ offset.call(node.start_line, node.start_column), offset.call(node.end_line, node.end_column) ]
      end

      # The new scalar in the style the old one had. A plain scalar that would read differently as
      # plain YAML (a leading quote, `: `, ` #`, `true`, a number) is written double-quoted instead.
      def render(entry, text, old)
        case entry.node.style
        when Psych::Nodes::Scalar::SINGLE_QUOTED
          text.include?("\n") ? double_quoted(text) : "'#{text.gsub("'", "''")}'"
        when Psych::Nodes::Scalar::DOUBLE_QUOTED
          double_quoted(text)
        when Psych::Nodes::Scalar::LITERAL, Psych::Nodes::Scalar::FOLDED
          block(entry, text, old)
        else
          plain_safe?(text) ? text : double_quoted(text)
        end
      end

      def double_quoted(text)
        escaped = text.gsub("\\", "\\\\\\\\").gsub('"', '\"').gsub("\n", "\\n").gsub("\t", "\\t")
        %("#{escaped}")
      end

      def plain_safe?(text)
        return false if text.empty? || text.include?("\n") || text != text.strip
        return false if text.match?(/\A[-?:,\[\]{}#&*!|>'"%@`]/) || text.include?(": ") || text.include?(" #") || text.end_with?(":")

        Psych.safe_load("v: #{text}")["v"] == text
      rescue Psych::Exception
        false
      end

      # Keeps the header (`>-`, `|+`), the indentation and any trailing blank lines of a block scalar.
      def block(entry, text, old)
        header, body = old.split("\n", 2)
        indent = body.to_s[/\A[ ]+/] || "  "
        trailing = body.to_s[/\n*\z/].to_s
        lines = if entry.node.style == Psych::Nodes::Scalar::FOLDED
          text.split("\n", -1)
        else
          text.chomp.split("\n", -1)
        end
        content = lines.map { it.empty? ? "" : "#{indent}#{it}" }.join("\n")
        "#{header}\n#{content}#{trailing.empty? ? "" : trailing}"
      end

      def check!(updated, locale, key, text, file)
        loaded = Psych.safe_load(updated, aliases: true, permitted_classes: [ Symbol, Date, Time ])
        value = [ locale.to_s, *key.to_s.split(".") ].reduce(loaded) { |node, name| node.is_a?(Hash) ? node[name] : nil }
        expected = value.is_a?(String) && value.end_with?("\n") && !text.end_with?("\n") ? value.chomp : value
        return if expected == text

        raise Error, "Tensaku couldn't write that value to #{file} without changing its meaning. Edit the file directly."
      rescue Psych::Exception => error
        raise Error, "The edit would break #{file} (#{error.message}). Nothing was written."
      end
    end
  end
end
