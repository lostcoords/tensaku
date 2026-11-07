require "test_helper"

class Tensaku::I18nMarkersTest < Tensaku::TestCase
  Markers = Tensaku::I18nMarkers

  def markers_in(text)
    text.scan(Markers::PATTERN).map { Markers.decode(it) }
  end

  test "encodes and decodes locale and key" do
    marker = Markers.encode(:es, "pages.home.título")

    assert_equal "es:pages.home.título", Markers.decode(marker)
    assert_match(/\A[⁣​‌‍⁠]+\z/, marker)
  end

  test "HTML pages mark translated text and attributes with their keys" do
    body = get("/").body

    assert_includes markers_in(body[%r{<h1.*?</h1>}m]), "en:pages.home.title"
    assert_includes markers_in(body[/placeholder="[^"]*"/]), "en:pages.home.search_placeholder"
    assert_includes markers_in(get("/?locale=es").body), "es:pages.home.title"
  end

  test "markers only appear while marking is on, and skip defaults and number keys" do
    assert_equal "Hello world", I18n.t("hello")

    Markers.with_markers do
      assert_equal [ "en:hello" ], markers_in(I18n.t("hello"))
      assert_empty markers_in(I18n.t("missing.key", default: "Fallback"))
      assert_empty markers_in(I18n.t("number.format.separator", default: "."))
      assert_kind_of Hash, I18n.t("pages.home")
    end
  end

  test "non-HTML responses and scripts lose their markers" do
    marked = "Hi#{Markers.encode(:en, "hello")}"
    app = ->(_) { [ 200, { "content-type" => "application/json" }, [ %({"a":"#{marked}"}) ] ] }
    html = ->(_) { [ 200, { "content-type" => "text/html" }, [ "<html><head></head><body><script>var a = '#{marked}'</script><p>#{marked}</p></body></html>" ] ] }

    assert_equal %({"a":"Hi"}), Tensaku::Middleware.new(app).call({ "PATH_INFO" => "/" })[2].join
    body = Tensaku::Middleware.new(html).call({ "PATH_INFO" => "/", "REQUEST_METHOD" => "GET" })[2].join
    assert_includes body, "<script>var a = 'Hi'</script>"
    assert_includes body, "<p>#{marked}</p>"
  end
end
