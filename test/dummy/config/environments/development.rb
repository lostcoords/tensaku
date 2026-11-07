Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.cache_store = :memory_store
  else
    config.action_controller.perform_caching = false
    config.cache_store = :null_store
  end

  config.active_support.deprecation = :log
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  config.action_view.annotate_rendered_view_with_filenames = true
  config.action_controller.raise_on_missing_callback_actions = true
  config.hosts.clear

  # The test suite runs this app in development (where Tensaku is on). Tests wrapped in the executor
  # would hold the load interlock that the view reloader needs after Tensaku writes a template.
  config.active_support.executor_around_test_case = false
end
