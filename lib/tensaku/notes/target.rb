module Tensaku
  module Notes
    # What a note points at, as the overlay sent it, with the file and line filled in from the source:
    # an element (a Herb stamp), a translation key, or a Markdown range.
    module Target
      KINDS = %w[element text translation markdown].freeze

      module_function

      # Fills in file positions from what the overlay saw: a Herb stamp, a translation key or a Markdown
      # range. A target whose source can't be read keeps what the page said about it.
      def from(raw)
        raise Error, "A note target must be a JSON object" unless raw.is_a?(Hash)

        raw = raw.stringify_keys
        kind = KINDS.include?(raw["kind"]) ? raw["kind"] : "element"
        target = { "kind" => kind, "text" => raw["text"]&.to_s&.truncate(500), "tag" => raw["tag"]&.to_s }

        if raw["stamp"].present?
          target["stamp"] = raw["stamp"].to_s
          path, line, column = Source::Template.parse_stamp(raw["stamp"])
          target["file"] = path
          target["range"] = "#{line}:#{column}"
          begin
            target.merge!(Source::Template.new(path).element_range(line, column).stringify_keys)
          rescue Error
            nil
          end
        end

        if kind == "translation"
          target["key"] = raw["key"].to_s
          target["locale"] = raw["locale"].to_s
          if (entry = Source::Locale.find(target["locale"], target["key"]))
            target["file"] = entry[:file]
            target["range"] = entry[:line].to_s
          end
        end

        if kind == "markdown" && raw["md"].present?
          target["md"] = raw["md"].to_s
          target["file"], target["range"] = raw["md"].to_s.split(/:(?=\d+:\d+-)/, 2)
        end

        point = raw["point"]
        target["point"] = point.map { it.to_f.clamp(0.0, 1.0).round(3) } if point.is_a?(Array) && point.size == 2 && point.all?(Numeric)
        target["classes"] = Array(raw["classes"]).map(&:to_s).grep(/\A[^\s]{1,80}\z/).first(12)
        target["context"] = raw["context"].to_h.slice("partials", "controller", "frame").transform_values { Array(it).map(&:to_s).first(10) }.compact_blank
        target.compact_blank
      end

      def rect(raw)
        return nil unless raw.is_a?(Hash)

        raw.to_h.stringify_keys.slice("x", "y", "width", "height").transform_values { it.to_f.round }
      end
    end
  end
end
