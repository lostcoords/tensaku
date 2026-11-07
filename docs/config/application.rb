require_relative "boot"

require "rails"
require "active_model/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

require "kiln/content"

module Docs
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.autoload_lib(ignore: %w[assets tasks])

    # The landing page's demo runs Tensaku's own prebuilt overlay.
    config.assets.paths << Rails.root.join("../app/assets")
  end
end
