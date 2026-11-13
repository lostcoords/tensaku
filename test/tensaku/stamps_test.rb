require "test_helper"

class Tensaku::StampsTest < Tensaku::TestCase
  test "views, partials, helpers and the layout carry Herb source stamps" do
    body = get("/").body

    assert_includes body, %(<h1 data-herb-source="app/views/pages/home.html.erb:2:3">)
    assert_includes body, %(data-herb-source="app/views/shared/_item.html.erb:1:18")
    assert_includes body, %(<nav data-herb-source="app/views/layouts/application.html.erb:10:5">)
  end

  test "helpers render as they do in production, attributes included" do
    body = get("/about").body

    assert_includes body, %(<a href="/">Back home</a>)
    assert_includes body, %(<div class="splatted" data-source="tag">Splatted</div>)
  end

  test "an app can turn on helper stamps, and Herb doesn't warn either way" do
    source = %(<%= link_to "Home", "/" %>)
    compile = ->(**options) { Herb::Engine.new(source, filename: "a.html.erb", project_path: "/", visitors: [ Tensaku::Railtie::SourceStamps.new ], **options).src }
    helpers = nil

    _out, warnings = capture_io do
      assert_not_includes compile.call, "data-herb-source"
      helpers = compile.call(parser_options: { action_view_helpers: true })
    end

    assert_includes helpers, %(<a href="/" data-herb-source="a.html.erb:1:1">Home</a>)
    assert_empty warnings
  end

  test "ViewComponent sidecar templates are stamped" do
    assert_includes get("/").body, %(<aside class="greeting-card" data-herb-source="app/components/greeting_component.html.erb:1:1">)
  end

  test "mailer previews render through Herb" do
    body = get("/rails/mailers/greeting_mailer/welcome.html?part=text%2Fhtml").body

    assert_includes body, %(<p class="mail-body" data-herb-source="app/views/greeting_mailer/welcome.html.erb:2:1">)
  end
end
