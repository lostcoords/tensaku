require "application_system_test_case"

# Dialogs opened with showModal() and popovers sit in the top layer, and a modal dialog makes the rest
# of the page inert. The overlay moves into the topmost one while it is open (top-layer.ts).
class TopLayerTest < ApplicationSystemTestCase
  setup do
    visit "/modals"
    wait_for_overlay
  end

  def open_modal
    find(".open-modal").click
    assert page.evaluate_script("document.getElementById('modal').open")
  end

  def host_parent
    page.evaluate_script("document.querySelector('tensaku-overlay').parentElement.id || document.querySelector('tensaku-overlay').parentElement.tagName")
  end

  # What the page hit-tests at the middle of an element of the overlay.
  def on_top?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const element = document.querySelector("tensaku-overlay").shadowRoot.querySelector(#{selector.to_json})
        const r = element.getBoundingClientRect()
        return document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2)?.tagName === "TENSAKU-OVERLAY"
      })()
    JS
  end

  def modal_open? = page.evaluate_script("document.getElementById('modal').open")

  test "in a modal dialog, the menu opens on top, takes clicks and keys, and the note saves while the dialog stays open" do
    open_modal
    find(".modal-text").click(:alt)

    assert overlay.has_css?(".menu")
    assert on_top?(".menu")
    assert_equal "modal", host_parent
    overlay.find(".menu button", text: "Add note").click
    overlay.find(".note-form textarea").set("Say more")
    overlay.find(".note-form button", text: "Save note").click

    assert_eventually { Tensaku::Notes.all.any? }
    assert_equal "p.modal-text", Tensaku::Notes.all.sole["targets"].first["tag"]
    assert modal_open?

    # The dock is outside the dialog's box: the app's click-outside handler never sees a click on it.
    assert on_top?(".corner")
    overlay.find(".corner").click
    assert overlay.has_css?(".dock.open")
    assert modal_open?
  end

  test "Escape closes Tensaku's menu first, and the dialog only after" do
    open_modal
    find(".modal-text").click(:alt)
    assert overlay.has_css?(".menu")

    press(:escape)
    assert overlay.has_no_css?(".menu")
    assert modal_open?

    press(:escape)
    assert_eventually { !modal_open? }
  end

  test "an area across a modal dialog leaves out what the dialog covers" do
    open_modal
    from = center_of(find(".modal-text")).map { it + 60 }
    drag(from, [ 4, 4 ], modifier: "Alt")

    where = overlay.find(".note-form .where").text
    assert_match(/modals\.html\.erb:(8|9|10):/, where)
    assert_no_match(/modals\.html\.erb:[1-5]:/, where)
    assert_no_match(/layouts/, where)
  end

  test "an area across an app's own CSS modal leaves out what it covers" do
    find(".open-overlay").click
    from = center_of(find(".css-modal-text")).map { it + 40 }
    drag(from, [ 4, 4 ], modifier: "Alt")

    where = overlay.find(".note-form .where").text
    assert_match(/modals\.html\.erb:(18|19):/, where)
    assert_no_match(/modals\.html\.erb:[1-5]:/, where)
  end

  test "select mode's arrow keys stay inside the modal dialog" do
    open_modal
    press(:alt, :shift, "KeyT")
    find(".modal-title").hover
    assert overlay.has_css?(".label", text: "h2.modal-title")

    3.times { press(:up) }
    assert overlay.has_css?(".label", text: "dialog#modal")
    press(:left)
    assert overlay.has_css?(".label", text: "dialog#modal")
  end

  test "nested dialogs: the overlay goes into the topmost, and back to the page after both close" do
    open_modal
    find(".open-nested").click
    find(".nested-text").click(:alt)
    assert overlay.has_css?(".menu")
    assert on_top?(".menu")
    assert_equal "nested", host_parent
    press(:escape)

    page.execute_script("document.getElementById('nested').close()")
    assert_eventually { host_parent == "modal" }
    page.execute_script("document.getElementById('modal').close()")
    assert_eventually { host_parent == "HTML" }
    assert_not page.evaluate_script("document.querySelector('tensaku-overlay').matches(':popover-open')")

    find(".behind-text").click(:alt)
    assert overlay.has_css?(".menu", text: "p.behind-text")
    assert on_top?(".menu")
  end

  test "an app's popover stays open while Tensaku's menu and note form are used" do
    find(".open-tip").click
    find(".tip-text").click(:alt)
    assert overlay.has_css?(".menu")
    assert on_top?(".menu")
    assert_equal "tip", host_parent

    overlay.find(".menu button", text: "Add note").click
    overlay.find(".note-form button", text: "Cancel").click
    assert page.evaluate_script("document.getElementById('tip').matches(':popover-open')")

    page.execute_script("document.getElementById('tip').hidePopover()")
    assert_eventually { host_parent == "HTML" }
  end
end
