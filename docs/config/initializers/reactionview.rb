# ReActionView comes with Tensaku, in development only.
if defined?(ReActionView)
  ReActionView.configure do |config|
    # Herb's dev tools wait for Herb's dev server, which these docs don't run.
    config.debug_mode = false
  end
end
