require "test_helper"

class Tensaku::McpTest < Tensaku::TestCase
  setup { Tensaku.root = tmp_root }
  teardown { Tensaku.root = nil }

  def rpc(method, params = {}, env: {})
    body = JSON.generate(jsonrpc: "2.0", id: 1, method:, params:)
    response = Rack::MockRequest.new(Rails.application).post("/__tensaku/mcp",
      { "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost:3000", "CONTENT_TYPE" => "application/json", input: body }.merge(env))
    [ response.status, (JSON.parse(response.body) if response.body.present?) ]
  end

  def tool(name, arguments = {})
    _, payload = rpc("tools/call", { name:, arguments: })
    payload["result"]
  end

  test "initializes and lists tools" do
    _, init = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } })
    assert_equal "2025-06-18", init.dig("result", "protocolVersion")

    _, tools = rpc("tools/list")
    assert_equal %w[list_notes get_note resolve_note ask_question watch_notes current_selection], tools.dig("result", "tools").map { it["name"] }
  end

  test "notifications get 202 and no body" do
    response = Rack::MockRequest.new(Rails.application).post("/__tensaku/mcp",
      "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost", input: JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))

    assert_equal 202, response.status
  end

  test "lists, resolves and questions notes" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section")

    listed = tool("list_notes")
    assert_includes listed.dig("content", 0, "text"), "Rename this section"
    assert_equal [ note["id"] ], listed.dig("structuredContent", "notes").map { it["id"] }

    tool("ask_question", id: note["id"], question: "Rename to what?")
    assert_equal "question", Tensaku::Notes.find(note["id"])["status"]

    tool("resolve_note", id: note["id"], reply: "Renamed in about.html.erb:1")
    assert_equal [ "resolved", "Renamed in about.html.erb:1" ], Tensaku::Notes.find(note["id"]).values_at("status", "reply")
    assert_empty tool("list_notes").dig("structuredContent", "notes")
  end

  test "watch_notes returns a note created while it waits" do
    since = Time.now.utc - 1
    Thread.new { sleep 0.3; Tensaku::Notes.create(url: "/", comment: "new one") }

    result = tool("watch_notes", since: since.iso8601, timeout_seconds: 5)

    assert_equal [ "new one" ], result.dig("structuredContent", "notes").map { it["comment"] }
  end

  test "unknown notes are tool errors, not crashes" do
    assert tool("get_note", id: "zzzz")["isError"]
  end

  test "refuses requests from web pages and other machines" do
    assert_equal 403, rpc("tools/list", env: { "HTTP_ORIGIN" => "https://evil.example" }).first
    assert_equal 403, rpc("tools/list", env: { "HTTP_HOST" => "evil.example" }).first
    assert_equal 403, rpc("tools/list", env: { "REMOTE_ADDR" => "10.1.1.1" }).first
    assert_equal 200, rpc("tools/list", env: { "HTTP_ORIGIN" => "http://localhost:3000" }).first
  end
end
