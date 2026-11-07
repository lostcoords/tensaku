require "test_helper"

class Tensaku::MarkdownTest < Tensaku::TestCase
  Markdown = Tensaku::Source::Markdown

  SOURCE = <<~MD
    ---
    title: Café
    ---

    ## Café *menu*

    A paragraph with **bold** text
    over two lines.

    - First item
    - Second item
  MD

  setup do
    Tensaku.root = tmp_root
    tmp_root.join("app/views/pages").mkpath
    @file = tmp_root.join("app/views/pages/menu.md")
    @file.write(SOURCE)
  end

  teardown { Tensaku.root = nil }

  test "a heading locks its hashes" do
    info = Markdown.new("app/views/pages/menu.md:5:1-5:16").describe(tag: "h2")

    assert_equal "## ", info[:prefix]
    assert_equal "Café *menu*", info[:text]
    assert info[:editable]
  end

  test "edits a multi-line paragraph and nothing else" do
    block = Markdown.new("app/views/pages/menu.md:7:1-8:15")
    info = block.describe(tag: "p")

    block.edit(original: info[:original], text: "A shorter paragraph.")

    assert_equal SOURCE.sub("A paragraph with **bold** text\nover two lines.", "A shorter paragraph."), @file.read
  end

  test "edits a list item after its marker, with multibyte text above" do
    Markdown.new("app/views/pages/menu.md:5:1-5:16").then { it.edit(original: it.describe[:original], text: "Café *carta*") }
    item = Markdown.new("app/views/pages/menu.md:11:1-11:13")

    item.edit(original: item.describe(tag: "li")[:original], text: "Last item")

    assert_equal SOURCE.sub("Café *menu*", "Café *carta*").sub("- Second item", "- Last item"), @file.read
  end

  test "refuses a stale block" do
    block = Markdown.new("app/views/pages/menu.md:7:1-8:15")
    original = block.describe[:original]
    @file.write(SOURCE.sub("bold", "strong"))

    assert_raises(Tensaku::StaleSource) { block.edit(original:, text: "x") }
  end

  test "lists are for notes, not edits" do
    refute Markdown.new("app/views/pages/menu.md:10:1-11:13").describe(tag: "ul")[:editable]
  end

  test "Markdown outside the writable paths is refused" do
    tmp_root.join("README.md").write("# Hi\n")

    assert_raises(Tensaku::Forbidden) { Markdown.new("README.md:1:1-1:4") }
  end
end
