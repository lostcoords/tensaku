require "application_system_test_case"

class MarkdownTest < ApplicationSystemTestCase
  test "Markdown blocks from a producer are edited in their source file" do
    visit "/guide"
    wait_for_overlay

    alt_click find(".guide h2")
    assert overlay.has_css?(".editor .chip", text: "##")
    type_in_editor "First steps"
    overlay.find(".editor .editable").send_keys(:enter)
    assert_selector ".guide h2", text: "First steps"

    alt_click find(".guide p")
    type_in_editor "Install the gem, then restart."
    overlay.find(".editor .editable").send_keys(:enter)
    assert_selector ".guide p", text: "Install the gem, then restart."

    assert_equal "---\ntitle: Guide\n---\n\n## First steps\n\nInstall the gem, then restart.\n", view("content/guide.md")
  end

  test "a note on a Markdown block points at the block, not at the stamped element around it" do
    visit "/guide"
    wait_for_overlay
    overlay.find(".corner").click
    overlay.find(".toolbar button", text: "Select").click

    find(".guide p").click
    overlay.find(".menu button", text: "Add note").click
    overlay.find(".note-form textarea").set("Say which gem")
    overlay.find(".note-form button", text: "Save note").click

    assert overlay.has_css?(".pin.open", text: "1")
    targets = Tensaku::Notes.all.sole["targets"]
    assert_equal [ [ "markdown", "content/guide.md", "7:1-8:19", "p" ] ], targets.map { it.values_at("kind", "file", "range", "tag") }
  end
end
