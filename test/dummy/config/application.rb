require_relative "boot"

require "rails"
require "active_model/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

# Required in every environment on purpose: the gem has to stay inert outside development even when
# an app lists it in the wrong Gemfile group.
require "tensaku"
require "view_component"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.autoload_lib(ignore: %w[assets tasks])
    config.i18n.available_locales = %i[en es]
    config.action_mailer.preview_paths = [ Rails.root.join("test/mailers/previews").to_s ]
  end
end
