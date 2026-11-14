require "application_system_test_case"

# Overlay behaviour on real host pages: undo, IME input, form state, Turbo history and duplicate loads.
class OverlayRobustnessTest < ApplicationSystemTestCase
  def save_editor
    overlay.find(".editor .editable", match: :first).send_keys(:enter)
  end

  def edit(selector, text)
    alt_edit find(selector)
    assert overlay.has_css?(".editor")
    type_in_editor text
    save_editor
    assert overlay.has_no_css?(".editor")
  end

  test "the corner button has a click cursor until a drag starts" do
    visit "/about"
    wait_for_overlay
    cursor = -> { page.evaluate_script(%(getComputedStyle(document.querySelector("tensaku-overlay").shadowRoot.querySelector(".corner")).cursor)) }
    x, y = page.evaluate_script(%((() => { const r = document.querySelector("tensaku-overlay").shadowRoot.querySelector(".corner").getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })()))

    assert_equal "pointer", cursor.call

    mouse.move(x, y)
    mouse.down
    mouse.move(x + 2, y)
    assert_equal "pointer", cursor.call, "a press that hasn't moved far enough isn't a drag"

    mouse.move(x - 40, y - 40)
    assert_equal "grabbing", cursor.call
    mouse.up
    assert_equal "pointer", cursor.call
    assert overlay.has_no_css?(".dock.open")
  end

  test "agent status lives on the Agents button: its tooltip stays hidden until hovered, and the corner button has no dot" do
    Tensaku::Agents.seen!(SecureRandom.hex(16), name: "Codex")
    visit "/about"
    wait_for_overlay
    style = ->(selector, property, pseudo = "null") { page.evaluate_script(%(getComputedStyle(document.querySelector("tensaku-overlay").shadowRoot.querySelector("#{selector}"), #{pseudo}).#{property})) }

    open_toolbar
    assert overlay.has_css?(".tool.agents.connected .icon-plane", visible: true, wait: 10)
    assert overlay.has_no_css?(".tool.agents .badge", visible: true)
    assert_equal "0", style.(".tool.agents .tip", "opacity")
    assert_equal "none", style.(".corner", "content", '"::before"')
  end

  test "the message after a save shows the changed line with the words marked" do
    visit "/about"
    wait_for_overlay
    edit "h1", "About us"

    assert overlay.has_css?(".toast .diff-row.removed mark", text: "me")
    assert overlay.has_css?(".toast .diff-row.added mark", text: "us")
    assert_match(/\ASaved app\/views\/.+:\d+/, overlay.find(".toast.detailed > span").text)
    assert overlay.has_css?(".toast.detailed button", text: "Undo")
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

    overlay.find(".toast", text: "About them").find("button", text: "Undo").click

    assert_selector "h1", text: "About us"
    assert_selector "p.bio", text: "Small tools."
    assert_includes view("app/views/pages/about.html.erb"), "<h1>About us</h1>"
    assert_includes view("app/views/pages/about.html.erb"), %(<p class="bio">Small tools.</p>)
  end

  test "an undo's toast offers Redo, which saves the edit again" do
    visit "/about"
    wait_for_overlay

    edit "h1", "About us"
    overlay.find(".toast button", text: "Undo").click
    assert_selector "h1", text: "About me"

    # Clicking Undo removed the first toast; the one left is the undo's own.
    assert overlay.has_css?(".toast", text: "Undid edit in app/views/pages/about.html.erb")
    assert overlay.has_no_css?(".toast button", text: "Undo")
    overlay.find(".toast button", text: "Redo").click
    assert_selector "h1", text: "About us"
    assert_includes view("app/views/pages/about.html.erb"), "<h1>About us</h1>"
  end

  test "Cmd/Ctrl+Z undoes saves newest first, Shift redoes them, and a new save clears what can be redone" do
    visit "/about"
    wait_for_overlay
    modifier = page.evaluate_script("/mac|iphone|ipad|ipod/i.test(navigator.platform || navigator.userAgent)") ? :meta : :control

    edit "h1", "About us"
    edit "p.bio", "Small tools."
    find("body").send_keys([ modifier, "z" ])
    assert_selector "p.bio", text: "I build"
    assert_selector "h1", text: "About us"
    find("body").send_keys([ modifier, "z" ])
    assert_selector "h1", text: "About me"

    find("body").send_keys([ modifier, :shift, "z" ])
    assert_selector "h1", text: "About us"
    assert_includes view("app/views/pages/about.html.erb"), "<h1>About us</h1>"

    edit "h1", "About them"
    find("body").send_keys([ modifier, :shift, "z" ])
    assert_selector "p.bio", text: "I build", wait: 1
    open_toolbar
    overlay.find(".toolbar button[aria-label='Edit history']").click
    assert overlay.has_no_css?(".popover .entry button", text: "Redo")
  end

  test "the edit history survives a reload, and a redo is refused when the file changed since" do
    visit "/about"
    wait_for_overlay
    edit "h1", "About us"
    overlay.find(".toast button", text: "Undo").click
    assert_selector "h1", text: "About me"

    visit "/about"
    wait_for_overlay
    open_toolbar
    overlay.find(".toolbar button[aria-label='Edit history']").click
    assert overlay.has_css?(".popover .entry.undone", text: "edit in app/views/pages/about.html.erb")

    file = Rails.root.join("app/views/pages/about.html.erb")
    file.write(file.read.sub("<h1>About me</h1>", "<h1>Changed elsewhere</h1>"))
    overlay.find(".popover .entry button", text: "Redo").click
    assert overlay.has_css?(".toast", text: "The text changed since the edit, so it can't be redone here.")
    assert_includes file.read, "<h1>Changed elsewhere</h1>"
  end

  test "Enter that confirms an IME composition doesn't save" do
    visit "/about"
    wait_for_overlay

    alt_edit find("h1")
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

  test "an attribute with a marker cut short is stripped once, and the page keeps running" do
    visit "/about"
    wait_for_overlay
    cut = Tensaku::I18nMarkers.encode(:en, "pages.about.title")[0, 9]

    page.execute_script("document.body.setAttribute('data-title', arguments[0])", "About#{cut}")

    assert_equal "About", page.evaluate_script("document.body.getAttribute('data-title')")
  end

  test "a translated heading stays editable after Back restores the page from Turbo's cache" do
    visit "/"
    wait_for_overlay
    find("nav a", text: "About").click
    assert_selector "h1", text: "About me"
    page.go_back
    assert_selector "h1", text: "Welcome home"

    alt_edit find("h1", text: "Welcome home")

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

    alt_edit find("h1")

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

  test "on a phone-sized screen the open toolbar and the editor's Save button stay on screen" do
    playwright { it.set_viewport_size(width: 430, height: 900) }
    visit "/"
    wait_for_overlay
    edges = ->(element) { page.evaluate_script("(() => { const r = arguments[0].getBoundingClientRect(); return [r.left, r.right] })()", element) }

    open_toolbar
    left, = edges.(overlay.find(".toolbar"))
    assert_operator left, :>=, 0

    alt_edit find("p.intro")
    _, right = edges.(overlay.find(".editor .bar button.primary", text: "Save"))
    assert_operator right, :<=, 430
  end
end
