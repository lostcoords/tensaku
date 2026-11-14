module Tensaku
  # In development, translated strings carry an invisible marker with their locale and key, so the
  # overlay knows which key produced a text or an attribute (the i18n_proofreading technique). The
  # overlay strips the markers when the page loads.
  #
  # A marker is U+2063 (invisible separator), then "locale:key" as UTF-8 bytes written in base 4 with
  # four zero-width characters, then U+2063 again. Nothing shows if the overlay never runs.
  #
  # Markers are only added while a controller handles an HTML request, never to `number.*`, `date.*`,
  # `time.*` and similar keys, never to a value that came from a `default:` instead of the key, and
  # never to pluralized lookups. A Ruby comparison against a translated string sees the marker, which
  # is the known cost of this technique (development only).
  module I18nMarkers
    FENCE = "⁣"
    DIGITS = [ "​", "‌", "‍", "⁠" ].freeze
    PATTERN = /#{FENCE}[#{DIGITS.join}]+#{FENCE}/o
    # What is left of a marker that the app cut short, such as a title truncated for a meta tag.
    CUT = /#{FENCE}[#{DIGITS.join}]*/o
    SKIP = /\A(?:number|date|time|datetime|support|i18n|helpers\.submit|errors\.format)(?:\.|\z)/

    module_function

    def active?
      Thread.current[:tensaku_i18n_markers] == true
    end

    def with_markers
      previous = Thread.current[:tensaku_i18n_markers]
      Thread.current[:tensaku_i18n_markers] = true
      yield
    ensure
      Thread.current[:tensaku_i18n_markers] = previous
    end

    def encode(locale, key)
      digits = "#{locale}:#{key}".bytes.flat_map { |byte| 3.downto(0).map { DIGITS[(byte >> (it * 2)) & 3] } }
      "#{FENCE}#{digits.join}#{FENCE}"
    end

    def decode(marker)
      digits = marker.delete(FENCE).chars.map { DIGITS.index(it) }
      digits.each_slice(4).map { |a, b, c, d| (a << 6) | (b << 4) | (c << 2) | d }.pack("C*").force_encoding(Encoding::UTF_8)
    end

    def strip(text)
      text.include?(FENCE) ? text.gsub(PATTERN, "").gsub(CUT, "") : text
    end

    # The raw value stored for the key, to tell a translation apart from a `default:` or a pluralized
    # hash. A Chain backend asks each of its backends in order. A backend without its own lookup (one
    # that only implements translate) gives nil, so its strings get no marker.
    def stored_value(backend, locale, key, options)
      if defined?(::I18n::Backend::Chain) && backend.is_a?(::I18n::Backend::Chain)
        backend.backends.each do |inner|
          value = stored_value(inner, locale, key, options)
          return value unless value.nil?
        end
        return nil
      end
      return nil if backend.method(:lookup).owner == ::I18n::Backend::Base

      backend.send(:lookup, locale, key, options[:scope], options)
    rescue NameError, NotImplementedError
      nil
    end

    # Added to the app's I18n backend with `extend`, so it wraps whichever backend the app uses.
    module Backend
      def translate(locale, key, options = ::I18n::EMPTY_HASH)
        result = super
        return result unless I18nMarkers.active? && result.is_a?(String) && !key.nil?

        full = ::I18n.normalize_keys(nil, key, options[:scope], options[:separator]).join(".")
        return result if full.match?(SKIP)
        return result unless I18nMarkers.stored_value(self, locale, key, options).is_a?(String)

        marked = result + I18nMarkers.encode(locale, full)
        result.html_safe? ? marked.html_safe : marked
      end
    end

    # A translated file name, such as a screenshot per locale, names an asset rather than text the
    # overlay can edit, so it resolves without its marker. Otherwise the asset lookup misses.
    # Both names, because Rails aliases one to the other and image_path calls the alias.
    module AssetPaths
      %i[asset_path path_to_asset].each do |name|
        define_method(name) do |source, options = {}|
          super(source.is_a?(String) ? I18nMarkers.strip(source) : source, options)
        end
      end
    end

    # Wraps controller actions for HTML requests.
    module Controller
      extend ActiveSupport::Concern

      included do
        prepend_around_action :tensaku_i18n_markers
      end

      private

      def tensaku_i18n_markers(&)
        return yield unless request.format&.html?

        I18nMarkers.with_markers(&)
      end
    end
  end
end
