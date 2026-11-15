require "test_helper"
require "open3"

# An app that loads only Action Controller, without Active Model, still boots in development.
class Tensaku::WithoutActiveModelTest < Tensaku::TestCase
  SCRIPT = <<~RUBY
    require "bundler/setup"
    require "tmpdir"
    require "rails"
    require "action_controller/railtie"
    require "tensaku"

    class NoModelApp < Rails::Application
      config.root = Dir.mktmpdir
      config.eager_load = false
      config.secret_key_base = "test"
      config.logger = Logger.new(nil)
    end
    NoModelApp.initialize!
    puts defined?(ActiveModel) ? "active-model" : "no-active-model"
  RUBY

  test "development boots without Active Model" do
    out, err, status = Open3.capture3({ "RAILS_ENV" => "development" }, "ruby", "-e", SCRIPT, chdir: File.expand_path("../..", __dir__))
    assert status.success?, err
    assert_equal "no-active-model", out.lines(chomp: true).last
  end
end
