# Tensaku turns on ERB interception and source attribution in development. The rest is ReActionView's
# own configuration.
if defined?(ReActionView)
  ReActionView.configure do |config|
    config.debug_mode = ENV["REACTIONVIEW_DEBUG"] == "1"
  end
end
