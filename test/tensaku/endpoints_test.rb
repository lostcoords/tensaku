require "test_helper"

class Tensaku::EndpointsTest < Tensaku::TestCase
  setup do
    Tensaku.root = tmp_root
    tmp_root.join("app/views/pages").mkpath
    @view = tmp_root.join("app/views/pages/hero.html.erb")
    @view.write(%(<section>\n  <h1 class="title">About me</h1>\n</section>\n))
  end

  teardown { Tensaku.root = nil }

  def request(method, path, body: nil, token: Tensaku.token, env: {})
    headers = { "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost:3000", "CONTENT_TYPE" => "application/json" }
    headers["HTTP_X_TENSAKU_TOKEN"] = token if token
    headers[:input] = JSON.generate(body) if body
    Rack::MockRequest.new(Rails.application).request(method, "/__tensaku#{path}", headers.merge(env))
  end

  def json(response) = JSON.parse(response.body)

  test "endpoints need the boot token and a loopback address" do
    assert_equal 403, request("GET", "/notes", token: nil).status
    assert_equal 403, request("GET", "/notes", token: "wrong").status
    assert_equal 403, request("GET", "/notes", env: { "REMOTE_ADDR" => "192.168.1.20" }).status
    assert_equal 200, request("GET", "/notes").status
  end

  test "the overlay script is served to loopback only" do
    assert_equal 200, request("GET", "/tensaku.js", token: nil).status
    assert_equal 403, request("GET", "/tensaku.js", token: nil, env: { "REMOTE_ADDR" => "10.0.0.2" }).status
  end

  test "describes and edits template text, then refuses the same stale edit" do
    info = json(request("GET", "/source?stamp=app/views/pages/hero.html.erb:2:3"))
    piece = info["pieces"].first
    edit = { stamp: info["stamp"], edits: [ { start: piece["start"], end: piece["end"], original: piece["raw"], text: "About us" } ] }

    response = request("POST", "/text", body: edit)

    assert_equal 200, response.status
    assert json(response)["changed"]
    assert_includes @view.read, %(<h1 class="title">About us</h1>)
    assert_equal 409, request("POST", "/text", body: edit.deep_merge(edits: [ edit[:edits][0].merge(text: "Again") ])).status
  end

test "tells edit mode which stamped elements have text written in the template" do
  tmp_root.join("app/views/pages/mixed.html.erb").write(<<~ERB)
    <section>
      <h1>Hello, <%= name %></h1>
      <p><%= body %></p>
      <img alt="A photo" src="a.png">
    </section>
  ERB
  stamps = %w[2:3 3:3 4:3].map { "app/views/pages/mixed.html.erb:#{it}" }
  response = request("POST", "/editable", body: { stamps: stamps + [ "config/database.yml:1:1", "app/views/pages/mixed.html.erb:40:1", "nonsense" ] })

  assert_equal 200, response.status
  assert_equal({
    "app/views/pages/mixed.html.erb:2:3" => true,
    "app/views/pages/mixed.html.erb:3:3" => false,
    "app/views/pages/mixed.html.erb:4:3" => false,
    "config/database.yml:1:1" => false,
    "app/views/pages/mixed.html.erb:40:1" => false,
    "nonsense" => false
  }, json(response)["editable"])
end

  test "writes outside the allow-list are refused" do
    tmp_root.join("config").mkpath
    tmp_root.join("config/x.html.erb").write("<p>x</p>")

    assert_equal 403, request("GET", "/source?stamp=config/x.html.erb:1:1").status
  end

  test "notes: create with file ranges, list, resolve, copy as Markdown, delete" do
    created = json(request("POST", "/notes", body: {
      url: "/about", comment: "Tighten this",
      targets: [ { kind: "element", stamp: "app/views/pages/hero.html.erb:2:3", text: "About me", context: { partials: [ "app/views/pages/hero.html.erb" ], controller: "hello" } } ],
      rect: { x: 1.4, y: 2, width: 300, height: 40 }, viewport: "1440x900"
    }))

    assert_equal "open", created["status"]
    target = created["targets"].first
    assert_equal [ "app/views/pages/hero.html.erb", "2:3-2:34", "h1.title" ], target.values_at("file", "range", "tag")
    assert tmp_root.join("tmp/tensaku/notes/#{created["id"]}.json").file?

    listed = json(request("GET", "/notes?url=/about"))
    assert_equal [ created["id"] ], listed["notes"].map { it["id"] }
    assert_equal false, listed.dig("agent", "connected")
    assert_equal 1, listed["open"]

    markdown = request("GET", "/notes.md?url=/about").body
    assert_includes markdown, "element `h1.title` at `app/views/pages/hero.html.erb:2:3-2:34` \"About me\""

    resolved = json(request("PATCH", "/notes/#{created["id"]}", body: { status: "resolved", reply: "Done" }))
    assert_equal [ "resolved", "Done" ], resolved.values_at("status", "reply")

    assert_equal 200, request("DELETE", "/notes/#{created["id"]}").status
    assert_empty Tensaku::Notes.all
  end

  test "notes: your answers go in the thread, a note moves to other elements, and copies in short form" do
    note = Tensaku::Notes.create(url: "/about", comment: "Tighten this", rect: { x: 1, y: 2, width: 3, height: 4 })
    Tensaku::Notes.update(note["id"], status: "question", message: "Tighten what?", agent: "Claude Code")

    answered = json(request("PATCH", "/notes/#{note["id"]}", body: { message: "The heading", status: "open" }))
    assert_equal [ [ "agent", "Tighten what?", "Claude Code" ], [ "you", "The heading", nil ] ], answered["thread"].map { it.values_at("from", "text", "agent") }
    assert_equal "Tighten what?", answered["reply"]
    assert_equal "Tighten this", answered["comment"]

    moved = json(request("PATCH", "/notes/#{note["id"]}", body: { targets: [ { kind: "element", stamp: "app/views/pages/hero.html.erb:2:3" } ] }))
    assert_equal [ "app/views/pages/hero.html.erb", "2:3-2:34" ], moved["targets"].sole.values_at("file", "range")
    assert_nil moved["rect"]

    markdown = request("GET", "/notes.md?url=/about").body
    assert_includes markdown, "> **Claude Code:** Tighten what?\n> **You:** The heading"
    assert_equal "- `#{note["id"]}` (open) Tighten this at `app/views/pages/hero.html.erb:2:3`", request("GET", "/notes.md?url=/about&format=short").body
  end

  test "editor links come from RAILS_EDITOR, for files inside the app only" do
    ActiveSupport::Editor.reset
    with_env("RAILS_EDITOR" => nil, "EDITOR" => nil) { assert_nil json(request("GET", "/editor?file=app/views/pages/hero.html.erb&line=2"))["url"] }
    ActiveSupport::Editor.reset
    with_env("RAILS_EDITOR" => "vscode") do
      url = json(request("GET", "/editor?file=app/views/pages/hero.html.erb&line=2"))["url"]
      assert_equal "vscode://file/#{tmp_root.join("app/views/pages/hero.html.erb").expand_path}:2", url
      assert_equal 422, request("GET", "/editor?file=../../etc/passwd&line=1").status
    end
  ensure
    ActiveSupport::Editor.reset
  end

  def with_env(values)
    old = values.keys.to_h { [ it, ENV[it] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| ENV[key] = value }
  end

  test "note ids can't reach outside the notes directory" do
    assert_equal 404, request("PATCH", "/notes/..%2F..%2Fx", body: { status: "resolved" }).status
    assert_raises(Tensaku::Notes::NotFound) { Tensaku::Notes.find("../../etc") }
  end

  test "resolved notes are pruned after a few days" do
    note = Tensaku::Notes.create(url: "/", comment: "old")
    Tensaku::Notes.update(note["id"], status: "resolved", reply: "ok")
    kept = Tensaku::Notes.create(url: "/", comment: "still open")

    Tensaku::Notes.prune!(now: Time.now + 4 * 24 * 3600)

    assert_equal [ kept["id"] ], Tensaku::Notes.all.map { it["id"] }
  end
end
