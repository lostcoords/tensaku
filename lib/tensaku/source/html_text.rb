module Tensaku
  module Source
    # Static HTML text as the browser shows it, mapped back to its source bytes.
    #
    # The source is cut into segments: one per character, one per entity (`&amp;`), and one per run
    # of whitespace (shown as a single space, or nothing at the edges of an element). An edit keeps the
    # source of every segment the edit didn't touch, so `&copy;` or a line break in the middle of a
    # paragraph survives an edit elsewhere in the same text.
    class HtmlText
      Segment = Data.define(:raw, :text)

      ENTITIES = {
        "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'", "nbsp" => "\u00A0",
        "copy" => "\u00A9", "reg" => "\u00AE", "trade" => "\u2122", "hellip" => "\u2026",
        "mdash" => "\u2014", "ndash" => "\u2013", "lsquo" => "\u2018", "rsquo" => "\u2019",
        "ldquo" => "\u201C", "rdquo" => "\u201D", "laquo" => "\u00AB", "raquo" => "\u00BB",
        "middot" => "\u00B7", "bull" => "\u2022", "euro" => "\u20AC", "pound" => "\u00A3",
        "times" => "\u00D7", "divide" => "\u00F7", "deg" => "\u00B0", "shy" => "\u00AD",
        "iexcl" => "\u00A1", "iquest" => "\u00BF", "larr" => "\u2190", "rarr" => "\u2192"
      }.freeze

      NBSP = "\u00A0"
      WHITESPACE = /\A[ \t\r\n\f]+\z/
      TOKEN = /&(?:#[xX]\h+|#\d+|[a-zA-Z][a-zA-Z0-9]*);|[ \t\r\n\f]+|./m

      attr_reader :segments

      # collapse: whitespace runs read as one space (HTML text), or stay as written (attribute values).
      # trim_start/trim_end: a whitespace run at that edge reads as nothing, as it does at the start or
      # end of a block element.
      def initialize(raw, collapse: true, trim_start: false, trim_end: false)
        @raw = raw
        tokens = raw.scan(TOKEN)
        @segments = tokens.each_with_index.map do |token, index|
          edge = (trim_start && index.zero?) || (trim_end && index == tokens.size - 1)
          Segment.new(token, decode(token, collapse:, edge:))
        end
      end

      def text
        segments.map(&:text).join
      end

      # The new source for this text after an edit, changing only the segments the edit touched.
      #
      # Browsers hand back a non-breaking space for `&nbsp;` and for runs of typed spaces, so the two
      # compare as equal: an untouched `&nbsp;` keeps its source, and a non-breaking space in the
      # changed part is written as a plain space.
      def rewrite(new_text, escape:)
        old_text = text.tr(NBSP, " ")
        new_text = new_text.tr(NBSP, " ")
        return @raw if new_text == old_text

        prefix = common_prefix(old_text, new_text)
        suffix = common_suffix(old_text, new_text, limit: [ old_text.length, new_text.length ].min - prefix)

        head = take_segments(segments, prefix)
        tail = take_segments(segments.reverse, suffix).reverse
        head_length = head.sum { it.text.length }
        tail_length = tail.sum { it.text.length }
        middle = new_text[head_length...(new_text.length - tail_length)]

        head.map(&:raw).join + escape.call(middle) + tail.map(&:raw).join
      end

      def self.escape_text(text)
        text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

      def self.attribute_escaper(quote)
        lambda do |text|
          escaped = text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
          quote == "'" ? escaped.gsub("'", "&#39;") : escaped.gsub('"', "&quot;")
        end
      end

      private

      def decode(token, collapse:, edge:)
        if token.match?(WHITESPACE)
          return token unless collapse

          edge ? "" : " "
        elsif token.start_with?("&") && token.length > 1
          decode_entity(token)
        else
          token
        end
      end

      def decode_entity(token)
        name = token[1...-1]
        code = if name.start_with?("#x", "#X") then name[2..].to_i(16)
        elsif name.start_with?("#") then name[1..].to_i
        end
        return [ code ].pack("U") if code&.between?(1, 0x10FFFF)

        ENTITIES.fetch(name, token)
      end

      def common_prefix(a, b)
        length = 0
        length += 1 while length < a.length && length < b.length && a[length] == b[length]
        length
      end

      def common_suffix(a, b, limit:)
        length = 0
        length += 1 while length < limit && a[-1 - length] == b[-1 - length]
        length
      end

      # The leading segments whose text fits entirely within `length` characters.
      def take_segments(list, length)
        taken = []
        used = 0
        list.each do |segment|
          break if used + segment.text.length > length

          used += segment.text.length
          taken << segment
        end
        taken
      end
    end
  end
end
