module Tensaku
  # Everything here is development only. In any other environment the railtie adds nothing, and
  # neither ReActionView nor Herb is loaded, so templates keep rendering with Erubi.
  class Railtie < Rails::Railtie
    if Rails.env.development?
      require "reactionview"
      require "herb/engine/visitors/source_attribution_visitor"

      # Before the app's initializers, so config/initializers/reactionview.rb can still adjust things.
      initializer "tensaku.reactionview", before: :load_config_initializers do
        ReActionView.configure do |config|
          config.intercept_erb = true
          config.engine.visitors.use(Herb::Engine::SourceAttributionVisitor.new)
        end
      end

      initializer "tensaku.middleware" do |app|
        app.middleware.insert_before 0, Tensaku::Middleware
      end

      initializer "tensaku.i18n" do
        ActiveSupport.on_load(:action_controller_base) do
          include Tensaku::I18nMarkers::Controller
        end
      end

      config.after_initialize do
        I18n.backend.extend(Tensaku::I18nMarkers::Backend) unless I18n.backend.is_a?(Tensaku::I18nMarkers::Backend)

        if (warning = Tensaku::Caches.fragment_cache_warning)
          Rails.logger.warn("[Tensaku] #{warning}")
        end
      end
    end
  end
end
