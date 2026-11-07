require "test_helper"
require "tensaku/source/html_text"

class Tensaku::HtmlTextTest < ActiveSupport::TestCase
  HtmlText = Tensaku::Source::HtmlText
  ESCAPE = HtmlText.method(:escape_text)

  test "decodes entities and collapses whitespace like a browser" do
    text = HtmlText.new("\n  Tensaku &amp; friends &copy;\n    edit &#x263A;\n", trim_start: true, trim_end: true)

    assert_equal "Tensaku & friends © edit ☺", text.text
  end

  test "keeps the source of segments the edit didn't touch" do
    text = HtmlText.new("Tensaku &amp; friends &copy; edit\n    this text.")

    assert_equal "Tensaku &amp; pals &copy; edit\n    this text.", text.rewrite("Tensaku & pals © edit this text.", escape: ESCAPE)
    assert_equal "Tensaku &amp; friends &copy; edit\n    this text!", text.rewrite("Tensaku & friends © edit this text!", escape: ESCAPE)
  end

  test "escapes new markup characters" do
    text = HtmlText.new("Hello")

    assert_equal "Hello &lt;b&gt; &amp; &lt;%= no %&gt;", text.rewrite("Hello <b> & <%= no %>", escape: ESCAPE)
  end

  test "an unchanged text returns the source untouched" do
    raw = "\n  Some   text\n"

    assert_equal raw, HtmlText.new(raw, trim_start: true, trim_end: true).rewrite("Some text", escape: ESCAPE)
  end

  test "trimmed edges keep their whitespace" do
    assert_equal "\n  Hi ", HtmlText.new("\n  Hello ", trim_start: true).rewrite("Hi ", escape: ESCAPE)
  end

  test "repeated characters shrink without duplicating" do
    assert_equal "aa", HtmlText.new("aaa").rewrite("aa", escape: ESCAPE)
    assert_equal "aaaa", HtmlText.new("aaa").rewrite("aaaa", escape: ESCAPE)
  end

  test "attribute values escape for their quote" do
    text = HtmlText.new(%(Say "hi" &amp; go), collapse: false)

    assert_equal %(Say "hi" &amp; go), text.text.then { text.rewrite(it, escape: HtmlText.attribute_escaper('"')) }
    assert_equal %(Say &quot;yo&quot; &amp; go), HtmlText.new(%(Say &quot;hi&quot; &amp; go), collapse: false).rewrite(%(Say "yo" & go), escape: HtmlText.attribute_escaper('"'))
    assert_equal "It&#39;s", HtmlText.new("Its", collapse: false).rewrite("It's", escape: HtmlText.attribute_escaper("'"))
  end

  test "unknown entities stay as written" do
    assert_equal "&bogus; x", HtmlText.new("&bogus; x").text
  end

  test "an untouched &nbsp; keeps its source, a typed non-breaking space is written as a space" do
    text = HtmlText.new("Price:&nbsp;10 euros")

    assert_equal "Price:&nbsp;20 euros", text.rewrite("Price:\u00A020 euros", escape: ESCAPE)
    assert_equal "Price:&nbsp;10 euros", text.rewrite("Price: 10 euros", escape: ESCAPE)
    assert_equal "Price:&nbsp;10 big euros", text.rewrite("Price:\u00A010\u00A0big euros", escape: ESCAPE)
  end
end
