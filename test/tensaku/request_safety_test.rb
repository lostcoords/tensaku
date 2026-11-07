require "test_helper"

# Who may reach the endpoints, and which responses get the overlay and its token.
class Tensaku::RequestSafetyTest < Tensaku::TestCase
  LOCAL = { "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost:3000" }.freeze

  setup { Tensaku.root = tmp_root }
  teardown { Tensaku.root = nil }

  def endpoint(method, path, env: {}, body: nil, token: Tensaku.token)
    headers = LOCAL.merge("CONTENT_TYPE" => "application/json")
    headers["HTTP_X_TENSAKU_TOKEN"] = token if token
    headers[:input] = body if body
    Rack::MockRequest.new(Rails.application).request(method, "/__tensaku#{path}", headers.merge(env))
  end

  def page(html, status: 200, env: {}, headers: {})
    app = ->(_) { [ status, { "content-type" => "text/html; charset=utf-8" }.merge(headers), [ html ] ] }
    Tensaku::Middleware.new(app).call(LOCAL.merge("PATH_INFO" => "/", "REQUEST_METHOD" => "GET").merge(env))
  end

  DOCUMENT = "<html><head></head><body><p>Hi</p></body></html>".freeze

  test "a page on another host name gets no token, so DNS rebinding can't read it" do
    assert_includes page(DOCUMENT)[2].join, "data-tensaku-token"
    assert_not_includes page(DOCUMENT, env: { "HTTP_HOST" => "evil.example" })[2].join, "data-tensaku-token"
  end

  test "error pages and fragments fetched by scripts get no overlay; form errors and framed fragments do" do
    assert_not_includes page(DOCUMENT, status: 403)[2].join, "data-tensaku-token"
    assert_includes page(DOCUMENT, status: 422)[2].join, "data-tensaku-token"
    assert_equal "<tr><td>Row</td></tr>", page("<tr><td>Row</td></tr>", env: { "HTTP_SEC_FETCH_DEST" => "empty" })[2].join
    assert_includes page("<p>Mail</p>", env: { "HTTP_SEC_FETCH_DEST" => "iframe" })[2].join, "data-tensaku-token"
  end

  test "the script carries the page's CSP nonce and the app's script name" do
    body = page(DOCUMENT, env: { "SCRIPT_NAME" => "/app", Tensaku::Middleware::NONCE => "abc123" })[2].join

    assert_includes body, %(data-tensaku-root="/app/__tensaku")
    assert_match %r{<script src="/app/__tensaku/tensaku\.js\?v=\w+" nonce="abc123"}, body
  end

  test "pages that aren't valid UTF-8, files and streams pass through untouched" do
    latin1 = "<html><head></head><body>caf\xE9</body></html>".b
    assert_equal latin1, page(latin1)[2].join.b

    file = Struct.new(:to_path) { def each = yield("<html><body></body></html>") }.new("/tmp/x.html")
    app = ->(_) { [ 200, { "content-type" => "text/html" }, file ] }
    assert_same file, Tensaku::Middleware.new(app).call(LOCAL.merge("PATH_INFO" => "/"))[2]
  end

  test "endpoints refuse another Host or Origin even with the right token" do
    assert_equal 200, endpoint("GET", "/notes").status
    assert_equal 403, endpoint("GET", "/notes", env: { "HTTP_HOST" => "evil.example" }).status
    assert_equal 403, endpoint("GET", "/notes", env: { "HTTP_ORIGIN" => "http://evil.example" }).status
    assert_equal 403, endpoint("GET", "/notes", env: { "HTTP_ORIGIN" => "null" }).status
    assert_equal 200, endpoint("GET", "/notes", env: { "HTTP_HOST" => "myapp.localhost", "HTTP_ORIGIN" => "http://myapp.localhost" }).status
    assert_equal 200, endpoint("GET", "/notes", env: { "HTTP_HOST" => "[::1]:3000" }).status
  end

  test "a host the app lists in config.hosts counts as local" do
    hosts = Rails.application.config.hosts
    Rails.application.config.hosts = [ IPAddr.new("0.0.0.0/0"), "myapp.test" ]

    assert_equal 200, endpoint("GET", "/notes", env: { "HTTP_HOST" => "myapp.test" }).status
    assert_equal 403, endpoint("GET", "/notes", env: { "HTTP_HOST" => "other.test" }).status
  ensure
    Rails.application.config.hosts = hosts
  end

  test "requests a proxy forwarded from another machine are refused" do
    assert_equal 403, endpoint("GET", "/notes", env: { "HTTP_X_FORWARDED_FOR" => "203.0.113.9" }).status
    assert_equal 403, endpoint("GET", "/notes", env: { "HTTP_FORWARDED" => "for=203.0.113.9;proto=https" }).status
    assert_equal 403, endpoint("GET", "/tensaku.js", token: nil, env: { "HTTP_X_FORWARDED_FOR" => "203.0.113.9" }).status
    assert_equal 200, endpoint("GET", "/notes", env: { "HTTP_X_FORWARDED_FOR" => "127.0.0.1" }).status
  end

  test "bad request bodies are answered with an error, not a crash" do
    assert_equal 422, endpoint("POST", "/notes", body: "[1, 2]").status
    assert_equal 422, endpoint("POST", "/notes", body: JSON.generate(comment: "Hi", targets: [ "nope" ])).status
    assert_equal 422, endpoint("GET", "/markdown?range=app/views/a.md:0:1-1:1").status
  end

  test "the token is shared through a file, so every server process uses the same one" do
    assert_equal Tensaku.token, Tensaku.token_path.read.strip
    assert_match Tensaku::TOKEN, Tensaku.token
  end
end
