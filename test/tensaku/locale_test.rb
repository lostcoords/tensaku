require "test_helper"

class Tensaku::LocaleTest < Tensaku::TestCase
  Locale = Tensaku::Source::Locale

  YAML_SOURCE = <<~YAML
    # Copy for the dummy app. Comments must survive.
    en:
      hello: "Hello world"
      caf\u00E9: "Caf\u00E9 \u00E9t\u00E9"  # accents before the target
      pages:
        home:
          title: Welcome home   # trailing comment
          greeting: "Hi %{name}, welcome back"
          search: 'Search the site'
          intro: >-
            A folded paragraph
            over two lines.
          poem: |
            line one
            line two

          after: kept
  YAML

  setup do
    Tensaku.root = tmp_root
    tmp_root.join("config/locales").mkpath
    @file = tmp_root.join("config/locales/en.yml")
    @file.write(YAML_SOURCE)
    @load_path = I18n.load_path.dup
    I18n.load_path.replace([ @file.to_s ])
  end

  teardown do
    I18n.load_path.replace(@load_path)
    Tensaku.root = nil
  end

  def edit(key, text, original: nil)
    original ||= Locale.find("en", key).value
    Locale.edit("en", key, original:, text:)
  end

  test "finds a key with its file and line" do
    entry = Locale.find("en", "pages.home.title")

    assert_equal "config/locales/en.yml", entry.file
    assert_equal 7, entry.line
    assert_equal "Welcome home", entry.value
  end

  test "a plain value stays plain and keeps its trailing comment" do
    edit "pages.home.title", "Welcome back"

    assert_equal YAML_SOURCE.sub("title: Welcome home   #", "title: Welcome back   #"), @file.read
  end

  test "a plain value that would change meaning gets double quotes" do
    edit "pages.home.title", "yes: really #1"

    assert_includes @file.read, %(title: "yes: really #1"   # trailing comment)
    assert_equal "yes: really #1", Psych.safe_load(@file.read).dig("en", "pages", "home", "title")
  end

  test "quoting styles are kept and escaped" do
    edit "pages.home.search", "Search Bob's site"
    edit "hello", %(Say "hi" \\o/)

    assert_includes @file.read, "search: 'Search Bob''s site'"
    assert_includes @file.read, %(hello: "Say \\"hi\\" \\\\o/")
  end

  test "multibyte text before the value doesn't shift the splice" do
    edit "caf\u00E9", "Caf\u00E9 hiver"

    assert_includes @file.read, %(caf\u00E9: "Caf\u00E9 hiver"  # accents before the target)
  end

  test "block scalars keep their header, indentation and trailing blank lines" do
    edit "pages.home.intro", "A shorter paragraph."
    edit "pages.home.poem", "line one\nline 2\n"

    expected = YAML_SOURCE
      .sub("intro: >-\n        A folded paragraph\n        over two lines.", "intro: >-\n        A shorter paragraph.")
      .sub("line two\n", "line 2\n")
    assert_equal expected, @file.read
  end

  test "interpolations must stay the same" do
    error = assert_raises(Tensaku::Error) { edit "pages.home.greeting", "Hi there" }

    assert_match "%{name}", error.message
    edit "pages.home.greeting", "Hey %{name}!"
    assert_includes @file.read, %(greeting: "Hey %{name}!")
  end

  test "refuses a stale original" do
    assert_raises(Tensaku::StaleSource) { edit "pages.home.title", "New", original: "Something else" }
    assert_equal YAML_SOURCE, @file.read
  end

  test "files outside the writable paths are never found" do
    outside = tmp_root.join("vendor/en.yml")
    outside.dirname.mkpath
    outside.write("en:\n  vendored: x\n")
    I18n.load_path << outside.to_s

    assert_nil Locale.find("en", "vendored")
  end
end
