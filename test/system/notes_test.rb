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

    overlay.find(".sidebar .note-card.question textarea").set("The one in the header")
    overlay.find(".sidebar button", text: "Answer").click
    assert_eventually { Tensaku::Notes.find(note["id"])["status"] == "open" }
    assert_equal [ "you", "The one in the header" ], Tensaku::Notes.find(note["id"])["thread"].last.values_at("from", "text")
    assert overlay.has_css?(".sidebar .message.you", text: "The one in the header")
  end

  test "a note is edited from its card and goes back to the agent as open" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    Tensaku::Notes.update(note["id"], status: "resolved", reply: "Renamed it")

    visit "/about"
    wait_for_overlay
    overlay.find(".corner").click
    overlay.find(".toolbar button[aria-label='Notes']").click
    overlay.find(".sidebar .note-card button", text: "Edit").click
    overlay.find(".sidebar .note-card textarea").set("Rename it to About me")
    overlay.find(".sidebar .note-card button", text: "Save").click

    assert overlay.has_css?(".sidebar .note-card.open", text: "Rename it to About me")
    assert_equal [ "Rename it to About me", "open", nil ], Tensaku::Notes.find(note["id"]).values_at("comment", "status", "reply")
  end

  test "shift-click picks several elements for one note" do
    visit "/about"
    wait_for_overlay
    select_mode

    find("h1").click(:shift)
    find("p.bio").click(:shift)
    assert overlay.has_css?(".pick", text: "2 selected")
    overlay.find(".pick button", text: "Add note").click
    overlay.find(".note-form textarea").set("Same font for both")
    overlay.find(".note-form button", text: "Save note").click

    assert overlay.has_css?(".pin")
    note = Tensaku::Notes.all.sole
    assert_equal %w[h1 p.bio], note["targets"].map { it["tag"] }
    assert_nil note["rect"]
  end

  test "pins can be hidden, and the page's notes deleted with a second click" do
    Tensaku::Notes.create(url: "/about", comment: "One", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    Tensaku::Notes.create(url: "/", comment: "Elsewhere")

    visit "/about"
    wait_for_overlay
    overlay.find(".corner").click
    assert overlay.has_css?(".pin")
    overlay.find(".toolbar button[aria-label='Hide pins']").click
    assert overlay.has_no_css?(".pin")
    overlay.find(".toolbar button[aria-label='Show pins']").click
    assert overlay.has_css?(".pin")

    overlay.find(".toolbar button[aria-label=\"Delete this page's notes\"]").click
    assert_equal 2, Tensaku::Notes.all.size
    overlay.find(".toolbar button.confirm").click
    assert overlay.has_no_css?(".pin")
    assert_equal [ "Elsewhere" ], Tensaku::Notes.all.map { it["comment"] }
  end

  test "the page follows an agent: connected light, working pin, then resolved" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])

    visit "/about"
    wait_for_overlay
    overlay.find(".corner").click
    assert overlay.has_css?(".pin.open")
    assert overlay.has_no_css?(".agent-light")

    Tensaku::Notes.agent_seen!
    Tensaku::Notes.update(note["id"], status: "working", agent: "Claude Code")
    assert overlay.has_css?(".pin.working", wait: 8)
    assert overlay.has_css?(".agent-light")
    assert overlay.has_css?(".toast", text: "Claude Code started on \"Rename this section\"")

    Tensaku::Notes.update(note["id"], status: "resolved", message: "Renamed it", agent: "Claude Code")
    assert overlay.has_css?(".pin.resolved", wait: 8)
    assert overlay.has_css?(".toast", text: "Claude Code resolved")
  end

  test "arrow keys walk the stamped elements and Cmd+C copies the highlighted one" do
    visit "/"
    wait_for_overlay
    stub_clipboard
    select_mode

    find("li.item span.name", match: :first).hover
    assert overlay.has_css?(".label", text: "span.name")
    page.driver.browser.keyboard.type(:up)
    assert overlay.has_css?(".label", text: "li.item")
    page.driver.browser.keyboard.type(:down)
    assert overlay.has_css?(".label", text: "span.name")
    page.driver.browser.keyboard.type(:up)
    page.driver.browser.keyboard.type([ :ctrl, "c" ])

    assert_eventually { copied.present? }
    assert_includes copied, "app/views/shared/_item.html.erb:1:1"
    assert_includes copied, "<li.item>"
  end

  test "a note on selected text marks the phrase on the page" do
    visit "/about"
    wait_for_overlay
    select_mode
    page.execute_script(<<~JS)
      const text = document.querySelector("p.bio").firstChild;
      const range = document.createRange();
      range.setStart(text, 2); range.setEnd(text, 13);
      getSelection().removeAllRanges(); getSelection().addRange(range);
    JS
    # A real drag selects the text and ends in a click; a scripted click keeps the selection.
    page.execute_script(%q{document.querySelector("p.bio").dispatchEvent(new MouseEvent("click", { bubbles: true, composed: true }))})
    overlay.find(".menu button", text: "Note on selected text").click
    overlay.find(".note-form textarea").set("Say what kind")
    overlay.find(".note-form button", text: "Save note").click

    assert overlay.has_css?(".phrase")
    assert_equal [ "text", "build small" ], Tensaku::Notes.all.sole["targets"].first.values_at("kind", "text")
  end

  test "the agent's messages show as a thread, and a note moves to another element" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:9:1" } ])
    Tensaku::Notes.update(note["id"], message: "Which one?", agent: "Claude Code")

    visit "/about"
    wait_for_overlay
    overlay.find(".corner").click
    overlay.find(".toolbar button[aria-label='Notes (1)']").click
    assert overlay.has_css?(".sidebar .message.agent", text: "Which one?")
    assert overlay.has_css?(".sidebar .missing")

    overlay.find(".sidebar button", text: "Move").click
    find("h1").click
    assert overlay.has_css?(".pin.open")
    assert_equal "app/views/pages/about.html.erb:1:1", Tensaku::Notes.find(note["id"])["targets"].sole["stamp"]
  end

  test "the notes panel shows every page's notes, and copies them in short form" do
    Tensaku::Notes.create(url: "/about", comment: "Here", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    other = Tensaku::Notes.create(url: "/", comment: "On the home page")

    visit "/about"
    wait_for_overlay
    stub_clipboard
    overlay.find(".corner").click
    overlay.find(".toolbar button[aria-label='Settings']").click
    overlay.find(".popover button", text: "One line each").click
    overlay.find(".toolbar button[aria-label^='Notes']").click
    overlay.find(".sidebar .tabs button", text: "All pages").click
    assert overlay.has_css?(".sidebar a.page", text: "/")
    assert overlay.has_css?(".sidebar .note-card", text: "On the home page")

    overlay.find(".sidebar button", text: "Copy all open").click
    assert_eventually { copied.to_s.include?("- `#{other["id"]}` (open) On the home page") }
  end

  test "the history lists this page's saves and undoes the latest one" do
    visit "/about"
    wait_for_overlay
    alt_click find("h1")
    type_in_editor "About us"
    overlay.find(".editor button", text: "Save").click
    assert_selector "h1", text: "About us"

    overlay.find(".corner").click
    overlay.find(".toolbar button[aria-label='Edit history']").click
    assert overlay.has_css?(".popover .entry", text: "app/views/pages/about.html.erb")
    overlay.find(".popover .entry button", text: "Undo").click
    assert_selector "h1", text: "About me"
    assert_equal "<h1>About me</h1>", view("app/views/pages/about.html.erb").lines.first.chomp
  end

  test "open in editor explains RAILS_EDITOR when no editor is set" do
    ActiveSupport::Editor.reset
    old = [ ENV.delete("RAILS_EDITOR"), ENV.delete("EDITOR") ]
    visit "/about"
    wait_for_overlay
    select_mode
    find("h1").click
    overlay.find(".menu button", text: "Open in editor").click
    assert overlay.has_css?(".toast", text: "Set RAILS_EDITOR")
  ensure
    ENV["RAILS_EDITOR"], ENV["EDITOR"] = old if old
    ActiveSupport::Editor.reset
  end

  private

  def assert_eventually(timeout: 5)
    deadline = Time.now + timeout
    sleep 0.1 until yield || Time.now > deadline
    assert yield
  end
end
