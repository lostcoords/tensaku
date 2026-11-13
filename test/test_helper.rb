# Tensaku only switches on in development, so the dummy app runs in the development environment.
# This is the real gate, exercised as is, rather than a test-only switch.
ENV["RAILS_ENV"] = "development"

require_relative "dummy/config/environment"
require "rails/test_help"
require "rack/mock"
require "tmpdir"

# Every test gets a database of its own: TENSAKU_HOME points at a new folder, and the store opens a
# new connection when it changes.
module TensakuHome
  def before_setup
    @tensaku_home = Dir.mktmpdir("tensaku-home")
    ENV["TENSAKU_HOME"] = @tensaku_home
    super
  end

  def after_teardown
    super
    Tensaku::Store.reset! if defined?(Tensaku::Store)
    FileUtils.rm_rf(@tensaku_home)
  end
end
ActiveSupport::TestCase.include(TensakuHome)

module Tensaku
  class TestCase < ActiveSupport::TestCase
    # A throwaway copy of a file tree, removed afterwards.
    def tmp_root
      @tmp_root ||= Pathname(Dir.mktmpdir("tensaku-test"))
    end

    teardown { FileUtils.rm_rf(@tmp_root) if @tmp_root }

    def get(path, env = {})
      Rack::MockRequest.new(Rails.application).get(path, { "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost:3000" }.merge(env))
    end
  end
end
