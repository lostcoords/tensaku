require "application_system_test_case"

class NotesTest < ApplicationSystemTestCase
  def stub_clipboard
    page.execute_script("navigator.clipboard.writeText = async (text) => { window.__copied = text }")
  end

  def copied
    page.evaluate_script("window.__copied")
  end

  def select_mode
    open_toolbar
    overlay.find(".toolbar button[aria-label='Select']").click
  end

  test "the overlay loads with a corner button and the shortcut toggles select mode" do
    visit "/"
    wait_for_overlay

    assert overlay.has_css?(".corner svg.logo")
    assert overlay.has_no_css?(".toolbar", visible: true)
    find("body").send_keys([ :alt, :shift, "T" ])
    assert overlay.has_css?(".toolbar button[aria-pressed=true][aria-label=Select]")
  end

  test "the settings panel changes a tool's shortcut, moves keys another tool had, and resets them all" do
    visit "/"
    wait_for_overlay
    open_toolbar
    overlay.find(".toolbar button[aria-label='Settings']").click
    assert overlay.has_css?(".sidebar.settings header", text: "Settings")
    assert overlay.has_css?(".toolbar button[aria-label='Settings'][aria-pressed=true]")

    overlay.find(".settings button[aria-label='Change the shortcut for Pause animations']").click
    assert overlay.has_css?(".settings .keys.recording", text: "Press keys…")
    find("body").send_keys([ :alt, :shift, "e" ])
    assert overlay.has_css?(".settings .shortcut.changed", text: "Pause animations")
    assert overlay.has_css?(".settings button[aria-label='Change the shortcut for Edit']", text: "None")

    find("body").send_keys(:escape)
    assert overlay.has_no_css?(".sidebar.settings")
    find("body").send_keys([ :alt, :shift, "e" ])
    assert overlay.has_css?(".toolbar button[aria-label='Resume animations']")
    assert overlay.has_no_css?(".toolbar button[aria-pressed=true][aria-label=Edit]")

    find("body").send_keys([ :alt, :shift, "n" ])
    assert overlay.has_css?(".sidebar header", text: "Notes on /")
    overlay.find(".toolbar button[aria-label='Settings']").click
    assert overlay.has_no_css?(".sidebar header", text: "Notes on /")
    overlay.find(".settings h4 button", text: "Reset all").click
    assert overlay.has_no_css?(".settings .shortcut.changed")
    find("body").send_keys(:escape)
    find("body").send_keys([ :alt, :shift, "e" ])
    assert overlay.has_css?(".toolbar button[aria-pressed=true][aria-label=Edit]")
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

  test "a note's pin sits where the note was written on its element, and stays there when the element moves" do
    visit "/about"
    wait_for_overlay

    find("p.bio").click(:alt, :shift, x: 30, y: 6, offset: :top_left)
    overlay.find(".note-form textarea").set("Here")
    overlay.find(".note-form button", text: "Save note").click
    assert overlay.has_css?(".pin.open", text: "1")

    point = Tensaku::Notes.all.sole["targets"].first["point"]
    assert_operator point[0], :<, 0.2, "the click was near the left edge, not at the top right"
    pin_at = -> { page.evaluate_script(<<~JS) }
      (() => {
        const pin = document.querySelector("tensaku-overlay").shadowRoot.querySelector(".pin").getBoundingClientRect()
        const bio = document.querySelector("p.bio").getBoundingClientRect()
        return [pin.left + pin.width / 2 - bio.left, pin.top + pin.height / 2 - bio.top].map(Math.round)
      })()
    JS
    near = ->(at) { at.zip([ 30, 6 ]).all? { |got, want| (got - want).abs <= 1 } }
    assert near.call(pin_at.call), pin_at.call.inspect

    page.execute_script(%(Object.assign(document.querySelector("p.bio").style, { position: "relative", left: "120px", top: "40px" })))
    page.execute_script(%(dispatchEvent(new Event("resize"))))
    assert_eventually { near.call(pin_at.call) }
  end

  test "Alt+Shift-click opens the note form without entering select mode" do
    visit "/about"
    wait_for_overlay

    find("p.bio").click(:alt, :shift)
    overlay.find(".note-form textarea").set("Make this punchier")
    overlay.find(".note-form button", text: "Save note").click

    assert overlay.has_css?(".pin.open", text: "1")
    assert overlay.has_no_css?(".toolbar", visible: true)
    assert_equal "app/views/pages/about.html.erb", Tensaku::Notes.all.sole["targets"].first["file"]
    assert_equal [ "bio" ], Tensaku::Notes.all.sole["targets"].first["classes"]
    assert Tensaku::Notes.all.sole["sent_at"], "notes are sent when saved"
  end

  test "a note on a helper's output points at the nearest stamped ancestor" do
    visit "/about"
    wait_for_overlay

    find("a", text: "Back home").click(:alt, :shift)
    overlay.find(".note-form textarea").set("Reword this link")
    overlay.find(".note-form button", text: "Save note").click

    assert overlay.has_css?(".pin.open", text: "1")
    assert_equal "/about", page.current_path
    target = Tensaku::Notes.all.sole["targets"].first
    assert_includes target["text"], "Back home"
    assert_predicate target["file"], :present?
    assert_no_match %r{pages/about}, target["file"]
  end

  # p.bio is on line 2 when the note is written.
  def note_on_bio
    Tensaku::Notes.create(url: "/about", comment: "Make this punchier", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:2:1", tag: "p.bio", text: "I build small tools for big apps." } ])
  end

  def pin_offset_from(selector)
    page.evaluate_script(<<~JS)
      document.querySelector("tensaku-overlay").shadowRoot.querySelector(".pin").getBoundingClientRect().top - document.querySelector(#{selector.to_json}).getBoundingClientRect().top
    JS
  end

  test "a pin follows its element when the file's lines move" do
    note_on_bio
    File.write(Rails.root.join("app/views/pages/about.html.erb"), <<~ERB)
      <div>New first line</div>
      <h1>About me</h1>
      <div style="height: 800px"></div>
      <p class="bio">I build small tools for big apps.</p>
    ERB

    visit "/about"
    wait_for_overlay

    assert overlay.has_css?(".pin", visible: :all)
    assert_operator pin_offset_from("p.bio").abs, :<, 60
  end

  test "a pin stays on its element when only the text changed, and leaves when the element is gone" do
    note_on_bio
    File.write(Rails.root.join("app/views/pages/about.html.erb"), %(<h1>About me</h1>\n<p class="bio">A new bio.</p>\n))
    visit "/about"
    wait_for_overlay
    assert overlay.has_css?(".pin", visible: :all)

    File.write(Rails.root.join("app/views/pages/about.html.erb"), %(<h1>About me</h1>\n<h2>Something else</h2>\n))
    visit "/about"
    wait_for_overlay
    assert overlay.has_no_css?(".pin", visible: :all)
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

    Tensaku::Notes.update(note["id"], status: "resolved", message: "Rewrote the bio in about.html.erb:2")
    visit "/about"
    assert overlay.has_css?(".pin.resolved")
    overlay.find(".pin").click
    assert overlay.has_text?("Rewrote the bio in about.html.erb:2")
    overlay.find(".panel button[aria-label='Delete']").click
    assert overlay.has_no_css?(".pin")
    # Deleted on the server once its Undo has passed.
    overlay.find(".toast", text: "Note deleted").find("button", text: "Undo").click
    assert overlay.has_css?(".pin.resolved")
    assert_equal 1, Tensaku::Notes.all.size
    overlay.find(".pin").click
    overlay.find(".panel button[aria-label='Delete']").click
    assert overlay.has_no_css?(".pin")
    assert_eventually(timeout: 10) { Tensaku::Notes.all.empty? }
  end

  test "dragging an area collects the stamped elements inside it" do
    visit "/about"
    wait_for_overlay
    select_mode

    heading = center_of(find("h1"))
    link = center_of(find("a", text: "Back home"))
    drag([ 2, heading[1] - 30 ], [ 500, link[1] + 20 ])

    overlay.find(".note-form textarea").set("Too much spacing here")
    overlay.find(".note-form button", text: "Save note").click
    assert overlay.has_css?(".pin")

    note = Tensaku::Notes.all.sole
    # The link is inside the area too, but helper output has no stamp of its own.
    assert_equal %w[h1 p.bio], note["targets"].map { it["tag"] }
    assert note["rect"]["width"] > 400
    assert_match(/\A\d+x\d+\z/, note["viewport"])
  end

  test "the corner button opens and closes the dock without moving, and the tools stay on its center line" do
    visit "/about"
    wait_for_overlay
    rect = ->(selector) { page.evaluate_script(%(JSON.stringify(document.querySelector("tensaku-overlay").shadowRoot.querySelector(#{selector.to_json}).getBoundingClientRect()))).then { JSON.parse(it) } }
    closed = rect.call(".corner")

    open_toolbar
    assert_equal closed, rect.call(".corner")
    assert overlay.has_no_css?("button[aria-label='Close Tensaku']")
    overlay.find(".toolbar button[aria-label=Select]").click
    assert_in_delta closed["top"], rect.call(".tool[aria-pressed=true]")["top"], 0.5

    overlay.find(".toolbar button[aria-label^=Notes]").click
    assert overlay.has_css?(".sidebar", text: "No notes on this page")
    assert overlay.has_no_css?(".sidebar .copy-bar")
    assert_not_includes overlay.find(".sidebar").text, "null"
    overlay.find(".corner").click
    assert overlay.has_no_css?(".toolbar", visible: true)
    assert overlay.has_no_css?(".sidebar")
    assert_equal closed, rect.call(".corner")
  end

  test "each Escape closes one thing: a field, the note from a pin, the notes panel, the mode, then the toolbar" do
    note = Tensaku::Notes.create(url: "/about", comment: "Make it blink", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    Tensaku::Notes.update(note["id"], status: "question", message: "How fast?", agent: "Codex")
    visit "/about"
    wait_for_overlay
    open_toolbar
    overlay.find(".toolbar button[aria-label=Select]").click
    overlay.find(".toolbar button[aria-label^=Notes]").click
    assert overlay.has_css?(".sidebar header", text: "Notes on /about")
    overlay.find(".pin").click
    assert overlay.has_css?(".note-pop")
    overlay.find(".note-pop textarea").click

    press(:escape)
    assert overlay.has_css?(".note-pop")
    assert page.evaluate_script(%(!document.querySelector("tensaku-overlay").shadowRoot.activeElement?.matches("textarea"))), "Escape leaves the field first"
    press(:escape)
    assert overlay.has_no_css?(".note-pop")
    assert overlay.has_css?(".sidebar")
    press(:escape)
    assert overlay.has_no_css?(".sidebar")
    assert overlay.has_css?(".toolbar button[aria-label^=Notes][aria-pressed=false]")
    assert overlay.has_css?(".toolbar button[aria-label=Select][aria-pressed=true]")
    press(:escape)
    assert overlay.has_css?(".toolbar button[aria-label=Select][aria-pressed=false]")
    assert overlay.has_css?(".dock.open")
    press(:escape)
    assert overlay.has_no_css?(".dock.open")
  end

  test "the tools stay in place while the toolbar reveals them from the corner button" do
    with_motion
    visit "/about"
    wait_for_overlay
    positions = page.evaluate_async_script(<<~JS)
      const done = arguments[0], root = document.querySelector("tensaku-overlay").shadowRoot, seen = [], start = performance.now()
      const widths = []
      root.querySelector(".corner").click()
      const frame = () => {
        seen.push(Math.round(root.querySelector(".tool[aria-label=Settings]").getBoundingClientRect().x))
        widths.push(root.querySelector(".toolbar").getBoundingClientRect().width)
        performance.now() - start < 350 ? requestAnimationFrame(frame) : done({ seen, grew: new Set(widths).size > 3 })
      }
      requestAnimationFrame(frame)
    JS

    assert_equal 1, positions["seen"].uniq.size, positions["seen"].inspect
    assert positions["grew"]
  end

  test "Alt-drag draws an area without entering select mode" do
    visit "/about"
    wait_for_overlay

    heading = center_of(find("h1"))
    link = center_of(find("a", text: "Back home"))
    drag([ 2, heading[1] - 30 ], [ 500, link[1] + 20 ], modifier: "Alt")

    overlay.find(".note-form textarea").set("Too much spacing")
    overlay.find(".note-form button", text: "Save note").click
    assert overlay.has_css?(".pin")
    assert_equal %w[h1 p.bio], Tensaku::Notes.all.sole["targets"].map { it["tag"] }
    assert_equal "", page.evaluate_script("document.documentElement.style.cursor")
    assert overlay.has_no_css?(".menu")
  end

  test "the notes panel lists this page's notes and copies them as Markdown" do
    Tensaku::Notes.create(url: "/about", comment: "Rename this section", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    note = Tensaku::Notes.create(url: "/about", comment: "Which photo?", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:2:1" } ])
    Tensaku::Notes.update(note["id"], status: "question", message: "Which photo do you mean?")

    visit "/about"
    wait_for_overlay
    stub_clipboard
    open_toolbar
    overlay.find(".toolbar button[aria-label='Notes (2)']").click

    assert overlay.has_css?(".sidebar .note-card", count: 2)
    assert overlay.has_css?(".pin.question")
    assert overlay.has_css?(".sidebar > .note-card + .note-card + .copy-bar")
    overlay.find(".sidebar button", text: "Copy page").click
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
    Tensaku::Notes.update(note["id"], status: "resolved", message: "Renamed it")

    visit "/about"
    wait_for_overlay
    open_toolbar
    overlay.find(".toolbar button[aria-label='Notes']").click
    overlay.find(".sidebar .note-card button[aria-label='Edit']").click
    overlay.find(".sidebar .note-card textarea[aria-label='Edit note']").set("Rename it to About me")
    overlay.find(".sidebar .note-card button", text: "Save").click

    assert overlay.has_css?(".sidebar .note-card.open", text: "Rename it to About me")
    saved = Tensaku::Notes.find(note["id"])
    assert_equal [ "Rename it to About me", "open" ], saved.values_at("comment", "status")
    assert_equal "Renamed it", saved["thread"].sole["text"]
    assert overlay.has_css?(".sidebar .note-card .message", text: "Renamed it")
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
    open_toolbar
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

  test "the page follows an agent: connected dot on the Agents button, working pin, then resolved" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])

    visit "/about"
    wait_for_overlay
    overlay.find(".corner").click
    assert overlay.has_css?(".pin.open")
    assert overlay.has_css?(".tool.agents:not(.connected)")

    Tensaku::Agents.seen!(SecureRandom.hex(16), name: "Claude Code")
    Tensaku::Notes.update(note["id"], status: "working", agent: "Claude Code")
    assert overlay.has_css?(".pin.working", wait: 8)
    assert overlay.has_css?(".tool.agents.connected:not(.listening) .icon-plane")
    assert overlay.has_no_css?(".toast")

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
    press(:up)
    assert overlay.has_css?(".label", text: "li.item")
    press(:down)
    assert overlay.has_css?(".label", text: "span.name")
    press(:up)
    press(:ctrl, "c")

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

  test "the agent's messages show as a thread, and a missing element is said" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:9:1" } ])
    Tensaku::Notes.update(note["id"], message: "Which one?", agent: "Claude Code")

    visit "/about"
    wait_for_overlay
    open_toolbar
    overlay.find(".toolbar button[aria-label='Notes (1)']").click
    assert overlay.has_css?(".sidebar .message.agent", text: "Which one?")
    assert overlay.has_css?(".sidebar .missing", text: "Not found on this page any more.")
    assert overlay.has_no_css?(".sidebar button[aria-label='Move to another element']")
  end

  test "a change from a card shows at once, before the server answers, and goes back when it refuses" do
    note = note_on_bio
    visit "/about"
    wait_for_overlay
    # A second's delay on the way to the server; a reopen is refused.
    playwright do |page|
      page.route("**/notes/#{note["id"]}", ->(route, request) {
        next route.continue unless request.method == "PATCH"
        sleep 1
        next route.continue unless request.post_data.include?(%("open"))
        route.fulfill(status: 422, contentType: "application/json", body: JSON.generate(error: "Refused for the test"))
      })
    end
    overlay.find(".pin").click
    overlay.find(".note-pop button[aria-label='Mark as done']").click
    assert overlay.has_css?(".pin.resolved", wait: 0.5)
    assert overlay.has_css?(".note-pop .status", text: "Resolved", wait: 0.5)
    assert_eventually { Tensaku::Notes.find(note["id"])["status"] == "resolved" }

    overlay.find(".note-pop button[aria-label='Reopen']").click
    assert overlay.has_css?(".pin.open", wait: 0.5)
    assert overlay.has_css?(".toast.error", text: "Refused for the test")
    assert overlay.has_css?(".pin.resolved")
    assert overlay.has_css?(".note-pop .status", text: "Resolved")
  end

  test "done and reopen can be undone, reopening doesn't send the note, and Assign says when nothing would change" do
    session = SecureRandom.hex(16)
    Tensaku::Agents.seen!(session, name: "Claude Code")
    label = "Claude Code · #{Tensaku::Agents.handle(session)}"
    note = Tensaku::Notes.create(url: "/about", comment: "Shorter", to: Tensaku::Agents.handle(session), targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:2:1" } ])
    visit "/about"
    wait_for_overlay
    overlay.find(".pin").click
    assert overlay.has_css?(".note-pop .assign button[disabled]", text: "Assigned")
    overlay.find(".note-pop select").select("Anyone")
    assert overlay.has_css?(".note-pop .assign button:not([disabled])", text: "Assign")

    overlay.find(".note-pop button[aria-label='Mark as done']").click
    overlay.find(".toast", text: "Marked as done").find("button", text: "Undo").click
    assert overlay.has_css?(".pin.open")
    assert_eventually { Tensaku::Notes.find(note["id"])["status"] == "open" }

    # Clicking the toast closed the card.
    overlay.find(".pin").click
    overlay.find(".note-pop button[aria-label='Mark as done']").click
    assert_eventually { Tensaku::Notes.find(note["id"])["status"] == "resolved" }
    sent = Tensaku::Notes.find(note["id"])["sent_at"]
    overlay.find(".note-pop button", text: "Reopen").click
    assert overlay.has_css?(".toast", text: "Note reopened")
    assert_eventually { Tensaku::Notes.find(note["id"])["status"] == "open" }
    assert_equal sent, Tensaku::Notes.find(note["id"])["sent_at"], "not sent to the agent again"
    assert_equal label, Tensaku::Notes.find(note["id"])["agent"]
  end

  test "when an agent resolves a note, the page shows its change without a reload" do
    note = note_on_bio
    visit "/about"
    wait_for_overlay
    page.execute_script("window.sameDocument = true")
    File.write(Rails.root.join("app/views/pages/about.html.erb"), view("app/views/pages/about.html.erb").sub("I build small tools for big apps.", "I build sharp tools."))
    Tensaku::Notes.update(note["id"], status: "resolved", message: "Sharpened the bio", agent: "Codex")

    assert_selector "p.bio", text: "I build sharp tools.", wait: 8
    assert page.evaluate_script("window.sameDocument"), "morphed, not reloaded"
  end

  test "a card's buttons are Mark as done, Edit and Delete, and a declined note shows as done" do
    note = Tensaku::Notes.create(url: "/about", comment: "Make it blink", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])

    visit "/about"
    wait_for_overlay
    overlay.find(".pin").click
    assert_equal [ "Mark as done", "Edit", "Delete" ], overlay.all(".note-pop .tools button").map { it["aria-label"] }
    assert overlay.has_css?(".note-pop .status", text: "Unassigned")

    Tensaku::Notes.update(note["id"], status: "declined", message: "Blinking fails WCAG", agent: "Codex")
    assert overlay.has_css?(".toast", text: "Codex declined \"Make it blink\"", wait: 8)
    assert overlay.has_css?(".pin.declined")
    open_toolbar
    overlay.find(".toolbar button[aria-label^='Notes']").click
    assert overlay.has_css?(".sidebar .section", text: "Done (1)")
    assert overlay.has_css?(".sidebar .note-card.declined .status", text: "Declined")
    assert_equal [ "Reopen", "Edit", "Delete" ], overlay.all(".sidebar .note-card.declined .tools button").map { it["aria-label"] }
  end

  test "the panel names the agent listening, and Connect one opens the Agents popover with what to ask" do
    Tensaku::Notes.create(url: "/about", comment: "Rename this", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])

    visit "/about"
    wait_for_overlay
    stub_clipboard
    open_toolbar
    overlay.find(".toolbar button[aria-label='Notes (1)']").click
    assert overlay.has_css?(".sidebar .listener", text: "No agent listening")
    overlay.find(".sidebar .listener button", text: "Connect one").click
    assert overlay.has_css?(".popover h3", text: "Agents")
    assert overlay.has_css?(".popover .empty", text: "No agent connected.")
    assert overlay.has_css?(".popover .connect code", text: "bin/rails generate tensaku:install")
    overlay.find(".popover .connect button[aria-label='Copy Watch my Tensaku notes']").click
    assert_eventually { copied == "Watch my Tensaku notes" }

    codex, claude = SecureRandom.hex(16), SecureRandom.hex(16)
    Tensaku::Agents.seen!(codex, name: "Codex", last: { "tool" => "resolve_note", "note" => "ab12", "at" => Time.now.utc.iso8601 })
    codex_label = "Codex · #{Tensaku::Agents.handle(codex)}"
    assert overlay.has_css?(".popover .agent", text: /#{codex_label}.*Last resolved ab12 just now/m, wait: 8)
    assert overlay.has_css?(".popover .connect code", text: "Do my Tensaku notes")

    Tensaku::Agents.seen!(claude, name: "Claude Code", listening: true)
    claude_label = "Claude Code · #{Tensaku::Agents.handle(claude)}"
    assert overlay.has_css?(".popover .agent.listening", text: /#{claude_label}.*Waiting for your notes/m, wait: 8)
    assert overlay.has_no_css?(".popover .connect")
    # Listeners first; the rest fold into one line that expands.
    assert overlay.has_no_css?(".popover .agent", text: codex_label)
    overlay.find(".popover .idle-toggle", text: "1 more connected, not listening").click
    assert overlay.has_css?(".popover .agent:not(.listening)", text: codex_label)
    assert overlay.has_css?(".sidebar .listener.on", text: "#{claude_label} is checking for notes")
    assert overlay.has_css?(".tool.agents.listening .icon-plane-flying")
    assert overlay.has_css?(".tool.agents.listening .tip", text: "#{claude_label} listening", visible: :all)
    assert overlay.has_css?(".tool.agents .badge", text: "2")
  end

  test "an unassigned note is taken and started by the agent that checks, and a long thread starts at the agent's latest message" do
    session = SecureRandom.hex(16)
    Tensaku::Agents.seen!(session, name: "Codex", listening: true, cwd: Dir.pwd, started_at: Time.now.utc.iso8601)

    visit "/about"
    wait_for_overlay
    select_mode
    assert overlay.has_css?(".tool.agents.listening", wait: 8)
    find("p.bio").click
    overlay.find(".menu button", text: "Add note").click
    overlay.find(".note-form textarea").set("Rename this")
    assert overlay.has_css?(".note-form .hint", text: "saves")
    label = "Codex · #{Tensaku::Agents.handle(session)}"
    assert_equal "", overlay.find(".note-form select").value
    assert overlay.has_css?(".note-form select option[value='']", text: "Anyone")
    overlay.find(".note-form button", text: "Save note").click
    assert overlay.has_css?(".toast", text: "Note saved")

    note = Tensaku::Notes.all.sole
    assert_nil note["session"]
    overlay.find(".pin").click
    assert overlay.has_css?(".note-pop .status", text: "Unassigned")
    Tensaku::Notes.claim_sent(Time.now.utc - 60, Time.now.utc, session:, agent: label)
    # A shown note doesn't change under you, so open it again once the poll has the delivery.
    assert_eventually { overlay.find(".pin").click; overlay.has_css?(".note-pop .status", text: "#{label} is working", wait: 0.5) }

    %w[agent you agent you].each_with_index { |from, i| Tensaku::Notes.update(note["id"], from:, message: "#{from} #{i}", agent: ("Codex" if from == "agent")) }
    Tensaku::Notes.start(note["id"], agent: "Codex", session:)
    overlay.find(".toolbar .tool.agents").click
    assert overlay.has_css?(".popover .agent a.doing", text: "Working on #{note["id"]}: “Rename this”", wait: 8)

    assert_eventually { overlay.find(".pin").click; overlay.has_css?(".note-pop .thread .message", count: 2, wait: 0.5) }
    assert_equal [ "agent 2", "you 3" ], overlay.all(".note-pop .thread .message span:last-child").map(&:text)
    overlay.find(".note-pop .thread button.earlier", text: "Show 2 earlier messages").click
    assert overlay.has_css?(".note-pop .thread .message", count: 4)
  end

  test "a note is assigned to the session picked in the form, with a screenshot of the element, and can be reassigned from its card" do
    codex = SecureRandom.hex(16)
    claude = SecureRandom.hex(16)
    Tensaku::Agents.seen!(codex, name: "Codex")
    Tensaku::Agents.seen!(claude, name: "Claude Code", listening: true)
    codex_label = "Codex · #{Tensaku::Agents.handle(codex)}"
    claude_label = "Claude Code · #{Tensaku::Agents.handle(claude)}"

    visit "/about"
    wait_for_overlay
    select_mode
    assert overlay.has_css?(".tool.agents.listening", wait: 8)
    find("p.bio").click
    overlay.find(".menu button", text: "Add note").click
    overlay.find(".note-form textarea").set("Shorter")
    assert overlay.has_css?(".note-form .options input[type=checkbox]:checked")
    overlay.find(".note-form select").select("#{codex_label} (not listening)")
    overlay.find(".note-form button", text: "Save note").click
    assert overlay.has_css?(".toast", text: "Note saved and assigned to #{codex_label}")

    assert_eventually { Tensaku::Notes.all.sole["screenshot"] }
    note = Tensaku::Notes.all.sole
    assert_equal [ codex, codex_label ], note.values_at("session", "agent")
    shot = Tensaku::Notes.screenshot(note["id"])
    assert shot["png"].start_with?("\x89PNG".b)
    assert_operator shot["width"], :>, 40
    assert_empty Tensaku::Notes.claim_sent(Time.now.utc - 60, Time.now.utc, session: claude, agent: claude_label)

    assert_eventually { overlay.find(".pin").click; overlay.has_css?(".note-pop .screenshot img[src^='blob:']", wait: 0.5) }
    overlay.find(".note-pop select").select(claude_label)
    overlay.find(".note-pop .assign button", text: "Assign").click
    assert overlay.has_css?(".toast", text: "Note assigned to #{claude_label}")
    assert_equal claude, Tensaku::Notes.find(note["id"])["session"]
    assert_eventually { overlay.find(".pin").click; overlay.has_css?(".note-pop .status", text: "Assigned to #{claude_label}", wait: 0.5) }
  end

  test "a note in progress can be taken back from its session, and one whose session ended says anyone can take it" do
    claude = SecureRandom.hex(16)
    Tensaku::Agents.seen!(claude, name: "Claude Code")
    claude_label = "Claude Code · #{Tensaku::Agents.handle(claude)}"
    note = Tensaku::Notes.create(url: "/about", comment: "Shorter", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    Tensaku::Notes.start(note["id"], agent: claude_label, session: claude)

    visit "/about"
    wait_for_overlay
    overlay.find(".pin").click
    assert overlay.has_css?(".note-pop .status", text: "#{claude_label} is working")
    overlay.find(".note-pop .assign button", text: "Reassign").click
    assert overlay.has_css?(".toast", text: "Note unassigned")
    taken = Tensaku::Notes.find(note["id"])
    assert_equal "open", taken["status"]
    assert_nil taken["session"]
    error = assert_raises(Tensaku::Error) { Tensaku::Notes.update(note["id"], status: "resolved", message: "Done", session: claude, started: true) }
    assert_includes error.message, "isn't started"

    # A session whose process ended while working on a note.
    Tensaku::Notes.start(note["id"], agent: "Codex · gone-fox", session: SecureRandom.hex(16))
    assert_eventually { overlay.find(".pin").click; overlay.has_css?(".note-pop .status", text: "Codex · gone-fox stopped. Anyone can take it", wait: 0.5) }
  end

  test "on a page with thousands of elements, the screenshot is the element itself" do
    visit "/about"
    wait_for_overlay
    page.execute_script("const s = document.createElement('section'); for (let i = 0; i < 5000; i++) { const p = document.createElement('p'); p.textContent = 'Row ' + i; s.append(p) } document.querySelector('p.bio').before(s)")
    select_mode
    find("p.bio").click
    overlay.find(".menu button", text: "Add note").click
    overlay.find(".note-form textarea").set("Big page")
    overlay.find(".note-form button", text: "Save note").click

    assert_eventually { Tensaku::Notes.all.first&.dig("screenshot") }
    assert_operator Tensaku::Notes.all.sole["screenshot"]["height"], :<, 120, "drawn without the area around it"
  end

  test "the page says to restart the dev server when Tensaku's code changed since it started" do
    Tensaku::Build.singleton_class.alias_method(:real_stale?, :stale?)
    Tensaku::Build.define_singleton_method(:stale?) { true }
    visit "/about"
    wait_for_overlay
    assert overlay.has_css?(".toast.error", text: "Restart the dev server")
  ensure
    Tensaku::Build.singleton_class.alias_method(:stale?, :real_stale?)
  end

  test "the Agents popover shows the channel command, and a session with a live channel" do
    visit "/about"
    wait_for_overlay
    open_toolbar
    overlay.find(".toolbar .tool.agents").click
    assert overlay.has_css?(".popover .connect code", text: "claude --dangerously-load-development-channels server:tensaku")

    session = SecureRandom.hex(16)
    Tensaku::Agents.seen!(session, name: "Claude Code", listening: true, channel: true)
    assert overlay.has_css?(".popover .agent.live", text: "Live: notes reach its chat as you save them", wait: 8)
  end

  test "an agent started before Tensaku's code changed is marked in the Agents popover" do
    Tensaku::Agents.seen!(SecureRandom.hex(16), name: "Codex", version: "000000000000")
    visit "/about"
    wait_for_overlay
    open_toolbar
    overlay.find(".toolbar .tool.agents").click
    assert overlay.has_css?(".popover .agent .outdated", text: "Runs older Tensaku code")
  end

  test "with the box unticked, a note is saved without a screenshot" do
    visit "/about"
    wait_for_overlay
    select_mode
    find("p.bio").click
    overlay.find(".menu button", text: "Add note").click
    overlay.find(".note-form textarea").set("No picture")
    assert overlay.has_css?(".note-form .options .to button", text: "no agent connected, connect one")
    overlay.find(".note-form .options input[type=checkbox]").uncheck
    overlay.find(".note-form button", text: "Save note").click
    assert overlay.has_css?(".toast", text: "Note saved")
    assert_nil Tensaku::Notes.all.sole["screenshot"]
    overlay.find(".pin").click
    overlay.find(".note-pop .assign button", text: "connect one").click
    assert overlay.has_css?(".popover", text: "Set up once per project")
    assert_equal false, page.evaluate_script("JSON.parse(localStorage.getItem('tensaku:screenshots'))")
  end

  test "pausing stops the page's animations until resumed" do
    visit "/about"
    wait_for_overlay
    page.execute_script(<<~JS)
      document.querySelector("h1").animate([{ opacity: 1 }, { opacity: 0.2 }], { duration: 100000 })
    JS
    open_toolbar
    overlay.find(".toolbar button[aria-label='Pause animations']").click
    assert_equal [ "paused" ], page.evaluate_script("document.getAnimations().map(a => a.playState)")
    assert page.has_css?("style[data-tensaku-pause]", visible: :all)

    overlay.find(".toolbar button[aria-label='Resume animations']").click
    assert_equal [ "running" ], page.evaluate_script("document.getAnimations().map(a => a.playState)")
    assert page.has_no_css?("style[data-tensaku-pause]", visible: :all)
  end

  test "a note card has no copy button, and takes a message only after the agent spoke" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])

    visit "/about"
    wait_for_overlay
    overlay.find(".pin").click
    assert overlay.has_css?(".note-pop .status", text: "Unassigned")
    assert overlay.has_css?(".note-pop .source", text: "about.html.erb:1")
    assert overlay.has_no_css?(".note-pop textarea")
    assert overlay.has_no_css?(".note-pop button", text: "Copy")

    Tensaku::Notes.update(note["id"], status: "question", message: "To what?", agent: "Claude Code")
    assert overlay.has_css?(".pin.question", wait: 8)
    overlay.find(".pin").click
    assert overlay.has_css?(".note-pop .message.agent", text: "To what?")
    assert overlay.has_css?(".note-pop textarea")
  end

  test "a resolved note takes a request for changes and goes back to the agent as open" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    Tensaku::Notes.update(note["id"], status: "resolved", message: "Renamed it", agent: "Claude Code")

    visit "/about"
    wait_for_overlay
    open_toolbar
    overlay.find(".toolbar button[aria-label^='Notes']").click
    overlay.find(".sidebar .note-card.resolved textarea").set("Shorter, please")
    overlay.find(".sidebar button", text: "Ask for changes").click

    assert_eventually { Tensaku::Notes.find(note["id"])["status"] == "open" }
    assert_equal [ "you", "Shorter, please" ], Tensaku::Notes.find(note["id"])["thread"].last.values_at("from", "text")
    assert overlay.has_css?(".sidebar .message.you", text: "Shorter, please")
    assert overlay.has_no_css?(".sidebar textarea")
  end

  test "many agent changes at once become one toast, and resolved notes are archived from the panel" do
    notes = 6.times.map { |index| Tensaku::Notes.create(url: "/about", comment: "Note #{index}", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ]) }
    kept = Tensaku::Notes.create(url: "/about", comment: "Still open", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:2:1" } ])

    visit "/about"
    wait_for_overlay
    assert overlay.has_css?(".pin", count: 7)
    notes.each { Tensaku::Notes.update(it["id"], status: "resolved", message: "Done", agent: "Claude Code") }

    assert overlay.has_css?(".toast", text: "Claude Code resolved 6 notes", wait: 8)
    assert overlay.has_css?(".toast", count: 1)

    overlay.find(".toast button", text: "Show").click
    assert overlay.has_css?(".sidebar .section", text: "Done (6)")
    overlay.find(".sidebar .section button", text: "Archive done").click

    assert overlay.has_css?(".toast", text: "Archived 6 done notes")
    assert overlay.has_no_css?(".sidebar .section")
    assert_equal [ kept["id"] ], Tensaku::Notes.all.map { it["id"] }
    assert_equal 6, Tensaku::Notes.list(status: "archived").size

    overlay.find(".sidebar .tabs button", text: "Archive").click
    assert overlay.has_css?(".sidebar header", text: "Archived notes")
    assert overlay.has_css?(".sidebar .note-card", count: 6)
    overlay.first(".sidebar .note-card button[aria-label='Reopen']").click
    assert overlay.has_css?(".sidebar .note-card", count: 5)
    assert_equal 2, Tensaku::Notes.all.size, "the reopened note left the archive"
  end

  test "the notes panel shows every page's notes, and copies them in short form" do
    Tensaku::Notes.create(url: "/about", comment: "Here", targets: [ { kind: "element", stamp: "app/views/pages/about.html.erb:1:1" } ])
    other = Tensaku::Notes.create(url: "/", comment: "On the home page")

    visit "/about"
    wait_for_overlay
    stub_clipboard
    open_toolbar
    overlay.find(".toolbar button[aria-label='Settings']").click
    overlay.find(".settings button", text: "One line each").click
    overlay.find(".toolbar button[aria-label^='Notes']").click
    overlay.find(".sidebar .tabs button", text: "All pages").click
    assert overlay.has_css?(".sidebar a.page", text: "/")
    assert overlay.has_css?(".sidebar .note-card", text: "On the home page")

    overlay.find(".sidebar button", text: "Copy all").click
    assert_eventually { copied.to_s.include?("- `#{other["id"]}` (open) On the home page") }

    overlay.find(".sidebar .note-card", text: "On the home page").find("button[aria-label='Delete']").click
    assert overlay.has_no_css?(".sidebar .note-card", text: "On the home page")
    assert overlay.has_css?(".sidebar .note-card", text: "Here")
    assert_eventually(timeout: 10) { Tensaku::Notes.all.none? { it["id"] == other["id"] } }
  end

  test "the history lists this tab's saves and undoes the latest one" do
    visit "/about"
    wait_for_overlay
    alt_edit find("h1")
    type_in_editor "About us"
    overlay.find(".editor button", text: "Save").click
    assert_selector "h1", text: "About us"

    open_toolbar
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
end
