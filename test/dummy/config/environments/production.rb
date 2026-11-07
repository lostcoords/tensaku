Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.secret_key_base = "dummy-production-secret"
  config.log_level = :warn
  config.logger = Logger.new(nil)
  config.public_file_server.enabled = true
  config.assets.compile = true if config.respond_to?(:assets) && config.assets.respond_to?(:compile=)
  config.hosts.clear
end
