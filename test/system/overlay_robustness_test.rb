require "application_system_test_case"

# Overlay behaviour on real host pages: undo, IME input, form state, Turbo history and duplicate loads.
class OverlayRobustnessTest < ApplicationSystemTestCase
  def save_editor
    overlay.find(".editor .editable", match: :first).send_keys(:enter)
  end

  def edit(selector, text)
    alt_click find(selector)
    assert overlay.has_css?(".editor")
    type_in_editor text
    save_editor
    assert overlay.has_no_css?(".editor")
  end

  test "the toast's Undo reverts the save it reports, even when an element was edited before" do
    visit "/about"
    wait_for_overlay

    edit "h1", "About us"
    assert_selector "h1", text: "About us"
    edit "p.bio", "Small tools."
    assert_selector "p.bio", text: "Small tools."
    edit "h1", "About them"
    assert_selector "h1", text: "About them"

    overlay.all(".toast button", text: "Undo").last.click

    assert_selector "h1", text: "About us"
    assert_selector "p.bio", text: "Small tools."
    assert_includes view("app/views/pages/about.html.erb"), "<h1>About us</h1>"
    assert_includes view("app/views/pages/about.html.erb"), %(<p class="bio">Small tools.</p>)
  end

  test "a save made by Undo offers no Undo of its own" do
    visit "/about"
    wait_for_overlay

    edit "h1", "About us"
    overlay.find(".toast button", text: "Undo").click
    assert_selector "h1", text: "About me"

    # Clicking Undo removed the first toast; the one left is the undo's own save.
    assert overlay.has_css?(".toast", text: "Saved")
    assert overlay.has_no_css?(".toast button", text: "Undo")
  end

  test "Enter that confirms an IME composition doesn't save" do
    visit "/about"
    wait_for_overlay

    alt_click find("h1")
    assert overlay.has_css?(".editor")
    type_in_editor "日本"
    page.execute_script(<<~JS)
      const field = document.querySelector("tensaku-overlay").shadowRoot.querySelector(".editor .editable");
      field.focus();
      field.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", keyCode: 229, isComposing: true, bubbles: true, composed: true, cancelable: true }));
    JS

    assert overlay.has_css?(".editor")
    assert_includes view("app/views/pages/about.html.erb"), "<h1>About me</h1>"
  end

  test "values typed into the page's form survive the refresh after a save" do
    visit "/signup"
    wait_for_overlay
    fill_in "name", with: "Ada"
    path = Rails.root.join("app/views/pages/signup.html.erb")
    path.write(path.read + %(<p class="extra">Added on disk</p>\n))

    edit "label", "Full name"

    # The paragraph only arrives through the refetch and morph.
    assert_selector "p.extra", text: "Added on disk"
    assert_selector "label", text: "Full name"
    assert_equal "Ada", find("#name").value
  end

  test "a translated heading stays editable after Back restores the page from Turbo's cache" do
    visit "/"
    wait_for_overlay
    find("nav a", text: "About").click
    assert_selector "h1", text: "About me"
    page.go_back
    assert_selector "h1", text: "Welcome home"

    alt_click find("h1", text: "Welcome home")

    assert overlay.has_css?(".editor", text: "pages.home.title")
  end

  test "a second copy of the script adds no second set of listeners" do
    visit "/about"
    wait_for_overlay
    page.execute_script(<<~JS)
      const script = document.createElement("script");
      script.src = document.querySelector("script[data-tensaku-ui]").src;
      script.onload = () => { window.__secondLoaded = true };
      document.body.append(script);
    JS
    Timeout.timeout(5) { sleep 0.05 until page.evaluate_script("window.__secondLoaded === true") }

    alt_click find("h1")

    assert_equal 1, overlay.all(".editor").size
    assert_equal 1, page.evaluate_script("document.querySelectorAll('tensaku-overlay').length")
  end

  test "select mode leaves the arrow keys and Enter to a focused field of the page" do
    visit "/"
    wait_for_overlay
    find("body").send_keys([ :alt, :shift, "T" ])
    find("p.intro").hover
    assert overlay.has_css?(".box")
    page.execute_script("document.querySelector('input[type=search]').focus()")

    find("input[type=search]").send_keys(:enter)

    assert overlay.has_no_css?(".menu")
  end
end
