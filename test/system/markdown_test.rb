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
end
