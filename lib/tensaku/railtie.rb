module Tensaku
  # Everything here is development only. In any other environment the railtie adds nothing, and
  # neither ReActionView nor Herb is loaded, so templates keep rendering with Erubi.
  class Railtie < Rails::Railtie
    if Rails.env.development?
      require "reactionview"
      require "herb/engine/visitors/source_attribution_visitor"

      # Stamps without Herb's recommended `action_view_helpers`, which drops the attributes of
      # `tag.div(**attrs)` in Herb 0.11.2. Without it, helpers render as they do in production and
      # their output has no stamp of its own. An app can still set the option in
      # config/initializers/reactionview.rb to get those stamps.
      class SourceStamps < Herb::Engine::SourceAttributionVisitor
        def recommended_parser_options = super.except(:action_view_helpers)
      end

      # Before the app's initializers, so config/initializers/reactionview.rb can still adjust things.
      initializer "tensaku.reactionview", before: :load_config_initializers do
        ReActionView.configure do |config|
          config.intercept_erb = true
          # Herb's dev tools aren't needed here, and their script warns when Herb's dev server isn't running.
          config.debug_mode = false
          config.engine.visitors.use(SourceStamps.new)
        end
      end

      # The code this server runs, to tell the page when the files changed under it (Build.stale?).
      initializer "tensaku.build" do
        Tensaku::Build.started
      end

      initializer "tensaku.middleware" do |app|
        app.middleware.insert_before 0, Tensaku::Middleware
      end

      initializer "tensaku.i18n" do
        ActiveSupport.on_load(:action_controller_base) do
          include Tensaku::I18nMarkers::Controller
        end
        ActiveSupport.on_load(:action_view) do
          prepend Tensaku::I18nMarkers::AssetPaths
        end
      end

      config.after_initialize do
        I18n.backend.extend(Tensaku::I18nMarkers::Backend) unless I18n.backend.is_a?(Tensaku::I18nMarkers::Backend)
        [ ActiveModel::Type::ImmutableString, ActiveModel::Type::String ].each { it.prepend(Tensaku::I18nMarkers::ModelStrings) }

        if (warning = Tensaku::Caches.fragment_cache_warning)
          Rails.logger.warn("[Tensaku] #{warning}")
        end
      end
    end
  end
end
