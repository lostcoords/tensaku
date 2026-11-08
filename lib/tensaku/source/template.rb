require "herb"
require "tensaku/source/html_text"

module Tensaku
  module Source
    # An ERB template, read through Herb, addressed by the element stamps Herb's
    # SourceAttributionVisitor writes (`data-herb-source="path:line:col"`, 1-based).
    #
    # Pieces are the element's children as they are in the file: static text (editable), Ruby output
    # and control flow (locked), child elements (locked, edited on their own) and comments (hidden).
    class Template
      PARSE_OPTIONS = { track_locations: true, action_view_helpers: true }.freeze
      EXTENSIONS = %w[.erb].freeze

      # Attributes people read. `value` only counts on buttons.
      ATTRIBUTES = %w[alt title placeholder aria-label value].freeze
      BUTTON_INPUTS = %w[submit button reset].freeze

      OUTPUT_TAGS = %w[<%= <%==].freeze

      attr_reader :relative_path, :source

      def self.parse_stamp(stamp)
        match = stamp.to_s.match(/\A(?<path>.+):(?<line>\d+):(?<column>\d+)\z/)
        raise Error, "Not a source stamp: #{stamp.inspect}" unless match

        [ match[:path], match[:line].to_i, match[:column].to_i ]
      end

      def self.from_stamp(stamp)
        path, line, column = parse_stamp(stamp)
        [ new(path), line, column ]
      end

      # Whether each stamped element has text written in its template, for edit mode's outlines. An
      # element whose text all comes from Ruby (<%= %>) has nothing to edit. A stamp Tensaku can't read
      # (a file outside the allow-list, a line that moved) counts as not editable.
      def self.editable(stamps)
        templates = {}
        stamps.to_h do |stamp|
          path, line, column = parse_stamp(stamp)
          unless templates.key?(path)
            templates[path] = begin
              new(path)
            rescue Error
              nil
            end
          end
          [ stamp, templates[path]&.describe(line, column)&.fetch(:editable) || false ]
        rescue Error
          [ stamp, false ]
        end
      end

      def initialize(relative_path)
        @relative_path = relative_path
        @path = Guard.writable_file!(relative_path, extensions: EXTENSIONS)
        @source = File.read(@path, mode: "rb").force_encoding(Encoding::UTF_8)
        @line_starts = [ 0 ]
        @source.b.each_line { @line_starts << @line_starts.last + it.bytesize }
      end

      # What the overlay needs to edit or annotate the element written at line:column.
      def describe(line, column)
        element = element_at!(line, column)
        helper = !element.open_tag.is_a?(Herb::AST::HTMLOpenTagNode)
        pieces = helper ? [] : pieces_of(element)
        {
          file: relative_path,
          stamp: "#{relative_path}:#{line}:#{column}",
          range: range_label(element.location),
          tag: tag_label(element),
          helper:,
          editable: !helper && pieces.any? { it[:kind] == "text" && !it[:text].strip.empty? },
          pieces:,
          attributes: helper ? [] : attributes_of(element)
        }
      end

      # The file range of the element, for notes: "line:col-line:col".
      def element_range(line, column)
        element = element_at!(line, column)
        { range: range_label(element.location), tag: tag_label(element) }
      end

      # edits: [{ start:, end:, original:, text: }], byte ranges of text pieces with the source they had
      # when the page loaded, and the new text as shown in the browser.
      def edit_text(line, column, edits)
        element = element_at!(line, column)
        pieces = pieces_of(element).select { it[:kind] == "text" }

        replacements = edits.map do |edit|
          piece = pieces.find { it[:start] == edit[:start].to_i && it[:end] == edit[:end].to_i }
          stale! unless piece && piece[:raw] == edit[:original]

          text = HtmlText.new(piece[:raw], trim_start: piece[:trim_start], trim_end: piece[:trim_end])
          { start: piece[:start], end: piece[:end], text: text.rewrite(clean(edit[:text]), escape: HtmlText.method(:escape_text)) }
        end

        write(replacements)
      end

      def edit_attribute(line, column, name, edit)
        element = element_at!(line, column)
        attribute = attributes_of(element).find { it[:name] == name }
        stale! unless attribute
        raise Error, "#{name} has an unquoted value. Quote it in the template first." unless attribute[:quote]

        piece = attribute[:pieces].find { it[:kind] == "text" && it[:start] == edit[:start].to_i && it[:end] == edit[:end].to_i }
        stale! unless piece && piece[:raw] == edit[:original]

        rewritten = HtmlText.new(piece[:raw], collapse: false).rewrite(clean(edit[:text]), escape: HtmlText.attribute_escaper(attribute[:quote]))
        write([ { start: piece[:start], end: piece[:end], text: rewritten } ])
      end

      private

      def element_at!(line, column)
        finder = ElementFinder.new(line, column - 1)
        Herb.parse(source, **PARSE_OPTIONS).value.accept(finder)
        finder.found or stale!("No element starts at #{relative_path}:#{line}:#{column} any more. Reload the page.")
      end

      def stale!(message = nil)
        raise StaleSource, message || "#{relative_path} changed since the page was rendered. Reload the page and try again."
      end

      def write(replacements)
        replacements = replacements.reject { source.byteslice(it[:start]...it[:end]) == it[:text] }
        return { changed: false } if replacements.empty?

        updated = FileWrite.splice(source, replacements)
        FileWrite.atomic(@path, updated)
        { changed: true, file: relative_path, diff: FileWrite.diff(source, updated) }
      end

      # Browsers hand back "\n" line breaks; a file written with "\r\n" keeps them.
      def clean(text)
        text = text.to_s.delete("\r")
        source.include?("\r\n") ? text.gsub("\n", "\r\n") : text
      end

      def pieces_of(element)
        body = element.body
        body.each_with_index.map do |node, index|
          case node
          when Herb::AST::HTMLTextNode
            start, finish = byte_range(node.location)
            raw = source.byteslice(start...finish)
            trim_start = index.zero?
            trim_end = index == body.size - 1
            text = HtmlText.new(raw, trim_start:, trim_end:).text
            { kind: "text", start:, end: finish, raw:, text:, trim_start:, trim_end: }
          when Herb::AST::ERBContentNode
            opening = node.tag_opening.value
            if OUTPUT_TAGS.include?(opening)
              { kind: "ruby", code: node.content.value.strip }
            else
              { kind: "hidden" }
            end
          when Herb::AST::HTMLElementNode
            { kind: "element", tag: tag_label(node), label: label_of(node), stamp: stamp_of(node) }
          when Herb::AST::HTMLCommentNode, Herb::AST::ERBYieldNode
            { kind: "hidden" }
          else
            { kind: "ruby", code: summary_of(node) }
          end
        end
      end

      def attributes_of(element)
        tag = element.tag_name&.value.to_s.downcase
        nodes = element.open_tag.children.grep(Herb::AST::HTMLAttributeNode)
        type = static_attribute(nodes, "type").to_s.downcase

        nodes.filter_map do |node|
          name = attribute_name(node)
          next unless ATTRIBUTES.include?(name)
          next if name == "value" && !(tag == "button" || (tag == "input" && BUTTON_INPUTS.include?(type)))
          next unless node.value

          quote = node.value.quoted ? node.value.open_quote&.value : nil
          pieces = node.value.children.map do |child|
            case child
            when Herb::AST::LiteralNode
              start, finish = byte_range(child.location)
              raw = source.byteslice(start...finish)
              { kind: "text", start:, end: finish, raw:, text: HtmlText.new(raw, collapse: false).text }
            when Herb::AST::ERBContentNode
              { kind: "ruby", code: child.content.value.strip }
            else
              { kind: "ruby", code: summary_of(child) }
            end
          end
          { name:, quote:, pieces: }
        end
      end

      def attribute_name(node)
        node.name&.children&.filter_map { it.content if it.is_a?(Herb::AST::LiteralNode) }&.join&.downcase
      end

      def static_attribute(nodes, name)
        node = nodes.find { attribute_name(it) == name }
        node&.value&.children&.grep(Herb::AST::LiteralNode)&.map(&:content)&.join
      end

      def tag_label(element)
        tag = element.tag_name&.value.to_s.downcase
        return tag unless element.open_tag.respond_to?(:children)

        nodes = element.open_tag.children.grep(Herb::AST::HTMLAttributeNode)
        id = static_attribute(nodes, "id")
        classes = static_attribute(nodes, "class").to_s.split.first
        return "#{tag}##{id}" if id.present?
        return "#{tag}.#{classes}" if classes.present?

        tag
      end

      def label_of(element)
        text = element.body.filter_map do |child|
          case child
          when Herb::AST::HTMLTextNode then child.content
          when Herb::AST::HTMLElementNode then label_of(child)
          when Herb::AST::ERBContentNode then "…" if OUTPUT_TAGS.include?(child.tag_opening.value)
          end
        end.join.squish
        text.length > 40 ? "#{text[0, 39]}…" : text
      end

      def summary_of(node)
        opening = node.respond_to?(:content) && node.content.respond_to?(:value) ? node.content.value : nil
        (opening || node.class.name.demodulize).strip.lines.first.to_s.strip
      end

      def stamp_of(node)
        start = node.open_tag.location.start
        "#{relative_path}:#{start.line}:#{start.column + 1}"
      end

      # Herb positions are 1-based lines and 0-based character columns.
      def byte_offset(position)
        line_start = @line_starts.fetch(position.line - 1)
        line = source.b[line_start...@line_starts.fetch(position.line, source.bytesize)].force_encoding(Encoding::UTF_8)
        line_start + line[0, position.column].bytesize
      end

      def byte_range(location)
        [ byte_offset(location.start), byte_offset(location.end) ]
      end

      def range_label(location)
        "#{location.start.line}:#{location.start.column + 1}-#{location.end.line}:#{location.end.column + 1}"
      end

      class ElementFinder < Herb::Visitor
        attr_reader :found

        def initialize(line, column)
          super()
          @line = line
          @column = column
        end

        def visit_html_element_node(node)
          start = node.open_tag&.location&.start
          @found ||= node if start && start.line == @line && start.column == @column
          super unless @found
        end
      end
    end
  end
end
