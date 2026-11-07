module Tensaku
  # After a write, the next request has to see the new file. Rails' file watcher would notice too, but
  # only on its next check, and the page refetch right after a save can beat it.
  module Caches
    module_function

    def clear!(kind)
      case kind
      when :template
        ActionView::LookupContext::DetailsKey.clear
        ViewComponent::CompileCache.invalidate! if defined?(::ViewComponent::CompileCache)
      when :locale
        I18n.reload!
        ActionView::LookupContext::DetailsKey.clear
      when :markdown
        ActionView::LookupContext::DetailsKey.clear
      end
    end

    # `rails dev:cache` turns on fragment caching, and cached fragments keep showing the old text.
    def fragment_caching?
      !!ActionController::Base.perform_caching
    end

    def fragment_cache_warning
      return unless fragment_caching?

      "Fragment caching is on in development (rails dev:cache), so cached fragments can keep showing the old text."
    end
  end
end
