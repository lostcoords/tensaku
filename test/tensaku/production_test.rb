require "test_helper"
require "open3"

# The dummy app requires Tensaku in every environment, as if the gem sat in the wrong Gemfile group.
class Tensaku::ProductionTest < Tensaku::TestCase
  SCRIPT = <<~RUBY
    require "./test/dummy/config/environment"
    require "rack/mock"
    response = Rack::MockRequest.new(Rails.application).get("/", "REMOTE_ADDR" => "127.0.0.1")
    puts ActionView::Template.registered_template_handler(:erb).class.name
    puts defined?(ReActionView) ? "reactionview" : "no-reactionview"
    puts Rails.application.middleware.map(&:name).grep(/Tensaku|Herb/).join(",").then { it.empty? ? "no-middleware" : it }
    puts response.body.scan(/data-(?:herb|tensaku)-[\\w-]+|tensaku\\.js/).uniq.join(",").then { it.empty? ? "no-markup" : it }
  RUBY

  %w[production test].each do |env|
    test "#{env} renders with Erubi and loads nothing from Tensaku or ReActionView" do
      out, err, status = Open3.capture3({ "RAILS_ENV" => env }, "ruby", "-e", SCRIPT, chdir: File.expand_path("../..", __dir__))
      assert status.success?, err

      handler, reactionview, middleware, markup = out.lines(chomp: true).last(4)
      assert_equal "ActionView::Template::Handlers::ERB", handler
      assert_equal "no-reactionview", reactionview
      assert_equal "no-middleware", middleware
      assert_equal "no-markup", markup
    end
  end
end
