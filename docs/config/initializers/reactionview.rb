# ReActionView comes with Tensaku, in development only.
if defined?(ReActionView)
  ReActionView.configure do |config|
    # Herb's dev tools wait for Herb's dev server, which these docs don't run.
    config.debug_mode = false
    # Herb 0.11.2 compiles `tag.div(**attributes)` to a bare <div> with this option on, which breaks
    # lostcoords-ui's search and code blocks in development. Text in these pages is literal markup, so
    # it keeps its stamps without it.
    # PLAN.md, "Herb attribute splats", says when to remove this.
    config.engine.parser_options = { action_view_helpers: false }
  end
end
