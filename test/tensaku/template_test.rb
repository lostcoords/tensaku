require "test_helper"

class Tensaku::TemplateTest < Tensaku::TestCase
  Template = Tensaku::Source::Template

  setup do
    Tensaku.root = tmp_root
  end

  teardown { Tensaku.root = nil }

  def write_view(name, content)
    path = tmp_root.join("app/views/pages", name)
    path.dirname.mkpath
    path.write(content)
    path
  end

  def describe(name, line, column)
    Template.new("app/views/pages/#{name}").describe(line, column)
  end

  test "describes an element's pieces with Ruby locked" do
    write_view "a.html.erb", %(<div>\n  <p class="greeting">Hello <%= @user.name %>!</p>\n</div>\n)

    info = describe("a.html.erb", 2, 3)

    assert_equal "p.greeting", info[:tag]
    assert_equal "2:3-2:51", info[:range]
    assert info[:editable]
    assert_equal %w[text ruby text], info[:pieces].map { it[:kind] }
    assert_equal "Hello ", info[:pieces][0][:text]
    assert_equal "@user.name", info[:pieces][1][:code]
  end

  test "an unknown stamp is stale" do
    write_view "a.html.erb", "<p>Hi</p>\n"

    assert_raises(Tensaku::StaleSource) { describe("a.html.erb", 1, 2) }
  end

  test "edits static text around Ruby and keeps everything else byte for byte" do
    path = write_view "a.html.erb", %(<div>\n  <p class="greeting">Hello <%= @user.name %>!</p>\n  <p>Café &amp; more</p>\n</div>\n)
    piece = describe("a.html.erb", 2, 3)[:pieces][0]

    Template.new("app/views/pages/a.html.erb").edit_text(2, 3, [ piece.slice(:start, :end).merge(original: piece[:raw], text: "Welcome back, ") ])

    assert_equal %(<div>\n  <p class="greeting">Welcome back, <%= @user.name %>!</p>\n  <p>Café &amp; more</p>\n</div>\n), path.read
  end

  test "multibyte text before the target doesn't shift the splice" do
    path = write_view "a.html.erb", %(<p title="ééé">日本 <b>bold</b> tail</p>\n)
    pieces = describe("a.html.erb", 1, 1)[:pieces]
    tail = pieces.last

    Template.new("app/views/pages/a.html.erb").edit_text(1, 1, [ tail.slice(:start, :end).merge(original: tail[:raw], text: " end") ])

    assert_equal %(<p title="ééé">日本 <b>bold</b> end</p>\n), path.read
  end

  test "edits several pieces of one element at once" do
    path = write_view "a.html.erb", %(<p>One <%= x %> two <%= y %> three</p>\n)
    texts = describe("a.html.erb", 1, 1)[:pieces].select { it[:kind] == "text" }
    edits = texts.zip([ "Uno ", " dos ", " tres" ]).map { |piece, text| piece.slice(:start, :end).merge(original: piece[:raw], text:) }

    Template.new("app/views/pages/a.html.erb").edit_text(1, 1, edits)

    assert_equal %(<p>Uno <%= x %> dos <%= y %> tres</p>\n), path.read
  end

  test "refuses an edit when the file changed since the page rendered" do
    path = write_view "a.html.erb", %(<p>Hello</p>\n)
    piece = describe("a.html.erb", 1, 1)[:pieces][0]
    path.write(%(<p>Howdy</p>\n))

    assert_raises(Tensaku::StaleSource) do
      Template.new("app/views/pages/a.html.erb").edit_text(1, 1, [ piece.slice(:start, :end).merge(original: piece[:raw], text: "Hi") ])
    end
    assert_equal %(<p>Howdy</p>\n), path.read
  end

  test "escapes markup typed into text" do
    path = write_view "a.html.erb", %(<p>Hello</p>\n)
    piece = describe("a.html.erb", 1, 1)[:pieces][0]

    Template.new("app/views/pages/a.html.erb").edit_text(1, 1, [ piece.slice(:start, :end).merge(original: piece[:raw], text: "<%= system('x') %> & <b>") ])

    assert_equal %(<p>&lt;%= system('x') %&gt; &amp; &lt;b&gt;</p>\n), path.read
  end

  test "helper output and elements without static text aren't editable" do
    write_view "a.html.erb", %(<%= link_to "Home", "/" %>\n<h1><%= t(".title") %></h1>\n)

    assert describe("a.html.erb", 1, 1)[:helper]
    refute describe("a.html.erb", 1, 1)[:editable]
    refute describe("a.html.erb", 2, 1)[:editable]
  end

  test "child elements and control flow are locked pieces" do
    write_view "a.html.erb", %(<p><% if x %>Yes<% end %> and <a href="/x">docs</a><!-- note --></p>\n)

    kinds = describe("a.html.erb", 1, 1)[:pieces].map { it.slice(:kind, :tag, :label, :stamp).compact }

    assert_equal [ { kind: "ruby" }, { kind: "text" }, { kind: "element", tag: "a", label: "docs", stamp: "app/views/pages/a.html.erb:1:31" }, { kind: "hidden" } ], kinds.map { it.except(:code) }
  end

  test "edits attribute text and keeps its quoting" do
    path = write_view "a.html.erb", %(<img src="/x.png" alt='A "small" icon' title="Icon <%= n %>">\n<button value="Go">Go</button>\n)
    info = describe("a.html.erb", 1, 1)
    alt = info[:attributes].find { it[:name] == "alt" }[:pieces][0]

    Template.new("app/views/pages/a.html.erb").edit_attribute(1, 1, "alt", alt.slice(:start, :end).merge(original: alt[:raw], text: "It's an icon"))
    title = describe("a.html.erb", 1, 1)[:attributes].find { it[:name] == "title" }[:pieces][0]
    Template.new("app/views/pages/a.html.erb").edit_attribute(1, 1, "title", title.slice(:start, :end).merge(original: title[:raw], text: "Logo \"#"))

    assert_equal %(<img src="/x.png" alt='It&#39;s an icon' title="Logo &quot;#<%= n %>">\n<button value="Go">Go</button>\n), path.read
    assert_equal [ "value" ], describe("a.html.erb", 2, 1)[:attributes].map { it[:name] }
  end

  test "value on non-button inputs isn't offered" do
    write_view "a.html.erb", %(<input type="text" value="x" placeholder="Name">\n)

    assert_equal [ "placeholder" ], describe("a.html.erb", 1, 1)[:attributes].map { it[:name] }
  end

  test "refuses files outside the writable paths" do
    tmp_root.join("lib").mkpath
    tmp_root.join("lib/x.html.erb").write("<p>x</p>")

    assert_raises(Tensaku::Forbidden) { Template.new("lib/x.html.erb") }
    assert_raises(Tensaku::Forbidden) { Template.new("app/views/../../lib/x.html.erb") }
  end

  test "refuses symlinks that leave the writable paths" do
    tmp_root.join("app/views").mkpath
    tmp_root.join("secret.erb").write("<p>x</p>")
    File.symlink(tmp_root.join("secret.erb"), tmp_root.join("app/views/link.erb"))

    assert_raises(Tensaku::Forbidden) { Template.new("app/views/link.erb") }
  end

  test "keeps the file mode" do
    path = write_view "a.html.erb", %(<p>Hello</p>\n)
    path.chmod(0o640)
    piece = describe("a.html.erb", 1, 1)[:pieces][0]

    Template.new("app/views/pages/a.html.erb").edit_text(1, 1, [ piece.slice(:start, :end).merge(original: piece[:raw], text: "Hi") ])

    assert_equal 0o640, path.stat.mode & 0o777
    assert_equal [ "a.html.erb" ], path.dirname.children.map { it.basename.to_s }
  end
end
