require "test_helper"

class Tensaku::StampsTest < Tensaku::TestCase
  test "views, partials, helpers and the layout carry Herb source stamps" do
    body = get("/").body

    assert_includes body, %(<h1 data-herb-source="app/views/pages/home.html.erb:2:3">)
    assert_includes body, %(data-herb-source="app/views/shared/_item.html.erb:1:18")
    assert_includes body, %(<nav data-herb-source="app/views/layouts/application.html.erb:10:5">)
    assert_includes get("/about").body, %(<a href="/" data-herb-source="app/views/pages/about.html.erb:3:1">Back home</a>)
  end

  test "ViewComponent sidecar templates are stamped" do
    assert_includes get("/").body, %(<aside class="greeting-card" data-herb-source="app/components/greeting_component.html.erb:1:1">)
  end

  test "mailer previews render through Herb" do
    body = get("/rails/mailers/greeting_mailer/welcome.html?part=text%2Fhtml").body

    assert_includes body, %(<p class="mail-body" data-herb-source="app/views/greeting_mailer/welcome.html.erb:2:1">)
  end
end
