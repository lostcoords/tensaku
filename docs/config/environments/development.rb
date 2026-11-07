Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.active_support.deprecation = :log
  config.action_view.annotate_rendered_view_with_filenames = true
  config.secret_key_base = "docs-development"
end
