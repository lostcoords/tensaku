Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.action_mailer.delivery_method = :test
  config.active_support.deprecation = :stderr
  config.hosts.clear
end
