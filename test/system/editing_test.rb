require "application_system_test_case"

class EditingTest < ApplicationSystemTestCase
  def save_editor
    overlay.find(".editor .editable", match: :first).send_keys(:enter)
  end

  test "Alt-click edits template text and the page updates" do
    visit "/"
    wait_for_overlay

    alt_click find("p.intro")
    assert overlay.has_css?(".editor")
    type_in_editor "Tensaku & pals edit this text."
    save_editor

    assert_text "Tensaku & pals edit this text."
    assert_includes view("app/views/pages/home.html.erb"), %(<p class="intro">Tensaku &amp; pals edit this text.</p>)
  end

  test "Ruby output is a locked chip and only the static text changes" do
    visit "/"
    wait_for_overlay

    alt_click find("p.greeting")
    assert overlay.has_css?(".editor .chip", text: "@user.name")
    type_in_editor "Welcome back, ", field: 0
    save_editor

    assert_selector "p.greeting", text: "Welcome back, David!"
    assert_includes view("app/views/pages/home.html.erb"), %(<p class="greeting">Welcome back, <%= @user.name %>!</p>)
  end

  test "edit mode highlights editable text and a normal click edits" do
    visit "/about"
    wait_for_overlay

    overlay.find(".corner").click
    overlay.find(".toolbar button", text: "Edit").click
    assert overlay.has_css?(".box.edit", minimum: 2)
    find("p.bio").click
    type_in_editor "I build small tools."
    save_editor

    assert_selector "p.bio", text: "I build small tools."
    assert_includes view("app/views/pages/about.html.erb"), %(<p class="bio">I build small tools.</p>)
  end

test "edit mode doesn't outline text that comes from Ruby" do
  visit "/about"
  wait_for_overlay

  overlay.find(".corner").click
  overlay.find(".toolbar button", text: "Edit").click
  assert overlay.has_css?(".box.edit", minimum: 2)

  outlined = ->(selector) do
    page.evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector(#{selector.to_json}).getBoundingClientRect()
        const boxes = Array.from(document.querySelector("tensaku-overlay").shadowRoot.querySelectorAll(".box.edit"))
        return boxes.some((b) => Math.abs(parseFloat(b.style.left) - (r.left + scrollX)) < 2 && Math.abs(parseFloat(b.style.top) - (r.top + scrollY)) < 2)
      })()
    JS
  end
  assert outlined.("p.bio")
  assert_not outlined.("p.since")
end

  test "a partial rendered in a loop says it edits every copy" do
    visit "/"
    wait_for_overlay

    alt_click first("li.item")
    assert overlay.has_text?("this edits all 3 copies")
    type_in_editor " is ", field: 0
    save_editor

    assert_selector "li.item", text: "Tea is 3 euros"
    assert_selector "li.item", text: "Cake is 5 euros"
    assert_includes view("app/views/shared/_item.html.erb"), %(</span> is <%= item.price %> euros)
  end

  test "ViewComponent sidecar templates are edited and re-rendered" do
    visit "/"
    wait_for_overlay

    alt_click find(".greeting-card h2")
    type_in_editor "From a sidecar"
    save_editor

    assert_selector ".greeting-card h2", text: "From a sidecar"
    assert_includes view("app/components/greeting_component.html.erb"), "<h2>From a sidecar</h2>"
  end

  test "translations are edited in the locale file, with comments kept" do
    visit "/"
    wait_for_overlay

    alt_click find("h1")
    assert overlay.has_text?("en.pages.home.title")
    type_in_editor "Welcome, friend"
    save_editor

    assert_selector "h1", text: "Welcome, friend"
    assert_includes view("config/locales/en.yml"), "title: Welcome, friend   # trailing comment"
  end

  test "translation interpolations are locked and other locales can be edited together" do
    visit "/"
    wait_for_overlay

    alt_click find("p.welcome")
    assert overlay.has_css?(".editor .chip", text: "%{name}")
    overlay.find("button", text: "Other locales (1)").click
    type_in_editor "Hey ", field: 0
    type_in_editor "Hola de nuevo ", field: 2
    overlay.find(".editor button", text: "Save").click

    assert_selector "p.welcome", text: "Hey David, welcome back"
    assert_includes view("config/locales/en.yml"), %(greeting: "Hey %{name}, welcome back")
    assert_includes view("config/locales/es.yml"), %(greeting: "Hola de nuevo %{name}, bienvenido de nuevo")
  end

  test "attributes from the template and from translations are edited in a form" do
    visit "/"
    wait_for_overlay

    alt_click find("img[alt]")
    assert overlay.has_css?(".attr .name", text: "alt")
    type_in_editor "A tiny icon", field: 0
    overlay.find(".editor button", text: "Save").click
    assert_selector "img[alt='A tiny icon']"
    assert_includes view("app/views/pages/home.html.erb"), %(alt="A tiny icon")

    alt_click find("input[type=search]")
    assert overlay.has_css?(".attr .name", text: "placeholder (t)")
    type_in_editor "Find anything", field: 0
    overlay.find(".editor button", text: "Save").click
    assert_selector "input[placeholder='Find anything']"
    assert_includes view("config/locales/en.yml"), "search_placeholder: 'Find anything'"
  end

  test "one-step undo restores the previous text" do
    visit "/about"
    wait_for_overlay

    alt_click find("h1")
    type_in_editor "About us"
    save_editor
    assert_selector "h1", text: "About us"

    overlay.find(".toast button", text: "Undo").click
    assert_selector "h1", text: "About me"
    assert_includes view("app/views/pages/about.html.erb"), "<h1>About me</h1>"
  end

  test "a file changed since the page rendered is refused" do
    visit "/about"
    wait_for_overlay
    path = Rails.root.join("app/views/pages/about.html.erb")
    path.write(path.read.sub("I build small tools for big apps.", "Changed elsewhere."))

    alt_click find("p.bio")

    assert overlay.has_css?(".toast.error", text: "changed since the page was rendered")
    assert overlay.has_no_css?(".editor")
    assert_includes path.read, "Changed elsewhere."
  end

  test "mailer previews are editable" do
    visit "/rails/mailers/greeting_mailer/welcome?part=text%2Fhtml"
    wait_for_overlay

    alt_click find("p.mail-body")
    type_in_editor "Thanks for joining."
    save_editor

    assert_selector "p.mail-body", text: "Thanks for joining."
    assert_includes view("app/views/greeting_mailer/welcome.html.erb"), %(<p class="mail-body">Thanks for joining.</p>)
  end
end
