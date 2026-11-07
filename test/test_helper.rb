# Tensaku only switches on in development, so the dummy app runs in the development environment.
# This is the real gate, exercised as is, rather than a test-only switch.
ENV["RAILS_ENV"] = "development"

require_relative "dummy/config/environment"
require "rails/test_help"
require "rack/mock"
require "tmpdir"

module Tensaku
  class TestCase < ActiveSupport::TestCase
    # A throwaway copy of a file tree, removed afterwards.
    def tmp_root
      @tmp_root ||= Pathname(Dir.mktmpdir("tensaku-test"))
    end

    teardown { FileUtils.rm_rf(@tmp_root) if @tmp_root }

    def get(path, env = {})
      Rack::MockRequest.new(Rails.application).get(path, { "REMOTE_ADDR" => "127.0.0.1" }.merge(env))
    end
  end
end
