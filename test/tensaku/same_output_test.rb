require "test_helper"
require "open3"

# Development renders with Herb (plus stamps, markers and the overlay), production with Erubi. With
# Tensaku's and Herb's additions taken out, every page must be byte for byte the same.
class Tensaku::SameOutputTest < Tensaku::TestCase
  PATHS = %w[/ /about /plain /frames /frames/lazy /signup /guide].freeze

  SCRIPT = <<~RUBY
    require "./test/dummy/config/environment"
    require "rack/mock"
    require "json"
    pages = #{PATHS.inspect}.to_h { [ it, Rack::MockRequest.new(Rails.application).get(it, "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost").body ] }
    puts JSON.generate(pages)
  RUBY

  def normalize(html)
    html
      .gsub(/ data-herb-source="[^"]*"/, "")
      .gsub(/^.*reactionview\.esm-.*\n/, "")
      .gsub(Tensaku::I18nMarkers::PATTERN, "")
      .gsub(/<meta name="tensaku"[^>]*>/, "")
      .gsub(%r{<script src="/__tensaku/[^>]*></script>}, "")
      .gsub(%r{<script type="application/json" data-herb-diagnostics.*?</script>}m, "")
      .gsub(/<!-- (BEGIN|END) [^>]*-->/m, "")
      .gsub(/name="authenticity_token" value="[^"]*"/, "")
      .gsub(/<meta name="csrf-token" content="[^"]*"/, "")
  end

  test "development and production render the same pages once Herb's and Tensaku's markup is removed" do
    out, err, status = Open3.capture3({ "RAILS_ENV" => "production" }, "ruby", "-e", SCRIPT, chdir: File.expand_path("../..", __dir__))
    assert status.success?, err
    production = JSON.parse(out.lines.last)

    PATHS.each do |path|
      assert_equal normalize(production.fetch(path)), normalize(get(path).body), "#{path} differs between Herb and Erubi"
    end
  end
end
