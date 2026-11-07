require "application_system_test_case"

class NotesTest < ApplicationSystemTestCase
  def stub_clipboard
    page.execute_script("navigator.clipboard.writeText = async (text) => { window.__copied = text }")
  end

  def copied
    page.evaluate_script("window.__copied")
  end

  def select_mode
    overlay.find(".corner").click
    overlay.find(".toolbar button[aria-label='Select']").click
  end

  test "the overlay loads with a corner button and the shortcut toggles select mode" do
    visit "/"
    wait_for_overlay

    assert overlay.has_css?(".corner", text: "添")
    assert overlay.has_no_css?(".toolbar", visible: true)
    find("body").send_keys([ :alt, :shift, "T" ])
    assert overlay.has_css?(".toolbar button[aria-pressed=true][aria-label=Select]")
  end

  test "copy reference gives the file, line, partial chain, Stimulus controller" do
    visit "/"
    wait_for_overlay
    stub_clipboard
    select_mode

    first("li.item span.name").click
    overlay.find(".menu button", text: "Copy reference").click

    assert_eventually { copied.present? }
    assert_includes copied, "GET / → app/views/shared/_item.html.erb:1:18"
    assert_includes copied, %(<span.name> "Tea")
    assert_includes copied, "Partials: app/views/shared/_item.html.erb < app/views/pages/home.html.erb < app/views/layouts/application.html.erb"
    assert_includes copied, "Rendered 3 times on this page"
  end

  test "copy reference names the Stimulus controller, Turbo Frame and translation key" do
    visit "/frames"
    wait_for_overlay
    stub_clipboard
    select_mode
    find("p.framed").click
    overlay.find(".menu button", text: "Copy reference").click
    assert_eventually { copied.to_s.include?("Turbo Frame: #inline") }

    visit "/"
    wait_for_overlay
    stub_clipboard
    select_mode
    find("h1").click
    overlay.find(".menu button", text: "Copy reference").click
    assert_eventually { copied.to_s.include?("Translation: en.pages.home.title") }
    assert_includes copied, "Stimulus: hello"
  end

  test "a note on an element is saved with its file range, pinned, and turns green when resolved" do
    visit "/about"
    wait_for_overlay
    select_mode

    find("p.bio").click
    overlay.find(".menu button", text: "Add note").click
    overlay.find(".note-form textarea").set("Make this punchier")
    overlay.find(".note-form button", text: "Save note").click

    assert overlay.has_css?(".pin.open", text: "1")
    assert overlay.has_css?(".count", text: "1")
    note = Tensaku::Notes.all.sole
    assert_equal "/about", note["url"]
    assert_equal [ "element", "app/views/pages/about.html.erb", "2:1-2:53", "p.bio" ], note["targets"].first.values_at("kind", "file", "range", "tag")

    Tensaku::Notes.update(note["id"], status: "resolved", reply: "Rewrote the bio in about.html.erb:2")
    visit "/about"
    assert overlay.has_css?(".pin.resolved")
    overlay.find(".pin").click
    assert overlay.has_text?("Rewrote the bio in about.html.erb:2")
    overlay.find(".panel button", text: "Dismiss").click
    assert overlay.has_no_css?(".pin")
    assert_empty Tensaku::Notes.all
  end

  test "dragging an area collects the stamped elements inside it" do
    visit "/about"
    wait_for_overlay
    select_mode

    heading = find("h1").native.node.find_position
    link = find("a", text: "Back home").native.node.find_position
    mouse = page.driver.browser.mouse
    mouse.move(x: 2, y: heading[1] - 30)
    mouse.down
    mouse.move(x: 500, y: link[1] + 20, steps: 5)
    mouse.up

    overlay.find(".note-form textarea").set("Too much spacing here")
    overlay.find(".note-form button", text: "Save note").click
    assert overlay.has_css?(".pin")

    note = Tensaku::Notes.all.sole
    assert_equal %w[h1 p.bio a], note["targets"].map { it["tag"] }
    assert note["rect"]["width"] > 400
    assert_match(/\A\d+x\d+\z/, note["viewport"])
  end

  test "the notes panel lists this page's notes and copies them as Markdown" do
    Tensaku::Notes.create(url: "/about", comment: "Rename this section", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    note = Tensaku::Notes.create(url: "/about", comment: "Which photo?", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:2:1" } ])
    Tensaku::Notes.update(note["id"], status: "question", reply: "Which photo do you mean?")

    visit "/about"
    wait_for_overlay
    stub_clipboard
    overlay.find(".corner").click
    overlay.find(".toolbar button[aria-label='Notes (2)']").click

    assert overlay.has_css?(".sidebar .note-card", count: 2)
    assert overlay.has_css?(".pin.question")
    overlay.find(".sidebar button", text: "Copy page notes").click
    assert_eventually { copied.to_s.include?("Rename this section") }
    assert_includes copied, "at `app/views/pages/about.html.erb:1:1-1:18`"

    overlay.find(".sidebar textarea").set("The one in the header")
    overlay.find(".sidebar button", text: "Answer").click
    assert_eventually { Tensaku::Notes.find(note["id"])["status"] == "open" }
    assert_includes Tensaku::Notes.find(note["id"])["comment"], "Answer: The one in the header"
  end

  private

  def assert_eventually(timeout: 5)
    deadline = Time.now + timeout
    sleep 0.1 until yield || Time.now > deadline
    assert yield
  end
end
