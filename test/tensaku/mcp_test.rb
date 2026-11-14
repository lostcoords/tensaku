require "test_helper"

class Tensaku::McpTest < Tensaku::TestCase
  # Collects what the server writes, one JSON-RPC message per line.
  class Output
    def initialize = @lines = Queue.new
    def write(text) = text.each_line { @lines << JSON.parse(it) }
    def flush = nil
    def pop(timeout: 10) = @lines.pop(timeout:) || raise("no reply within #{timeout}s")
    def empty? = @lines.empty?
  end

  setup do
    Tensaku.root = tmp_root
    @output = Output.new
    @server = Tensaku::Mcp.new([ tmp_root ], output: @output)
    @ids = 0
  end

  teardown do
    @server.close
    Tensaku.root = nil
  end

  def rpc(method, params = {}, server: @server, output: @output)
    id = (@ids += 1)
    server.handle(JSON.generate(jsonrpc: "2.0", id:, method:, params:))
    reply = output.pop
    assert_equal id, reply["id"]
    reply
  end

  def tool(name, **arguments)
    rpc("tools/call", { name:, arguments: })["result"]
  end

  def tool_on(server, output, name, **arguments)
    rpc("tools/call", { name:, arguments: }, server:, output:)["result"]
  end

  def text(result) = result.dig("content", 0, "text")

  def initialize_as(title, server: @server, output: @output)
    rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: title.downcase, title:, version: "1" } }, server:, output:)
  end

  test "initializes, names the agent on the page, and lists tools" do
    init = initialize_as("Claude Code")

    assert_equal "2025-06-18", init.dig("result", "protocolVersion")
    assert_equal [ "Claude Code" ], Tensaku::Agents.list.map { it["name"] }
    assert_equal %w[list_notes get_note get_screenshot start_note resolve_note decline_note ask_question reply_to_note watch_notes channel_ready current_selection], rpc("tools/list").dig("result", "tools").map { it["name"] }
  end

  test "notifications get no reply, and bad JSON gets a parse error" do
    @server.handle(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))
    assert @output.empty?

    @server.handle("{ nope")
    assert_equal(-32700, @output.pop.dig("error", "code"))
  end

  test "lists, resolves and questions notes" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section")

    listed = tool("list_notes")
    assert_includes text(listed), "Rename this section"
    assert_includes text(listed), note["id"]
    assert_nil listed["structuredContent"]

    tool("ask_question", id: note["id"], question: "Rename to what?")
    assert_equal "question", Tensaku::Notes.find(note["id"])["status"]

    refused = tool("resolve_note", id: note["id"], reply: "Renamed")
    assert refused["isError"]
    assert_includes text(refused), "Call start_note before you change anything"
    tool("start_note", id: note["id"])
    assert_equal "Resolved note #{note["id"]}. No open notes left.", text(tool("resolve_note", id: note["id"], reply: "Renamed in about.html.erb:1"))
    saved = Tensaku::Notes.find(note["id"])
    assert_equal "resolved", saved["status"]
    assert_equal "Renamed in about.html.erb:1", saved["thread"].last["text"]
    assert_equal "No notes.", text(tool("list_notes"))
  end

  test "a note handed over by watch_notes is started for the session, so it resolves without start_note" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section")
    tool("watch_notes", since: (Time.now.utc - 5).iso8601, timeout_seconds: 1)

    saved = Tensaku::Notes.find(note["id"])
    assert_equal [ "working", @server.session.id ], saved.values_at("status", "session")
    assert_equal "Resolved note #{note["id"]}. No open notes left. Call watch_notes to keep listening.", text(tool("resolve_note", id: note["id"], reply: "Renamed"))
  end

  test "closing a note says how many open notes are left, and a listener is told to keep listening" do
    first = Tensaku::Notes.create(url: "/about", comment: "Rename this section")
    second = Tensaku::Notes.create(url: "/about", comment: "Shorter intro")
    tool("start_note", id: first["id"])
    assert_equal "Resolved note #{first["id"]}. 1 open note is left: list_notes has it.", text(tool("resolve_note", id: first["id"], reply: "Renamed"))

    tool("watch_notes", timeout_seconds: 1)
    assert_equal "Asked on note #{second["id"]}. No open notes left. Call watch_notes to keep listening.", text(tool("ask_question", id: second["id"], question: "How short?"))
  end

  test "Claude Code loads the tools of the work loop up front" do
    tools = rpc("tools/list").dig("result", "tools").to_h { [ it["name"], it.dig("_meta", "anthropic/alwaysLoad") ] }
    assert_equal Tensaku::Session::Tools::ALWAYS_LOAD.sort, tools.select { |_, always| always }.keys.sort
    assert_nil tools["get_screenshot"]
  end

  test "notes for agents give absolute file paths" do
    note = Tensaku::Notes.create(url: "/notes", comment: "Hyphenate", targets: [ { "kind" => "markdown", "md" => "app/views/pages/notes.html.md:3:1-3:12", "text" => "Follow up" } ])
    absolute = "`#{tmp_root.expand_path}/app/views/pages/notes.html.md:3:1-3:12`"
    assert_includes text(tool("list_notes")), absolute
    assert_includes text(tool("get_note", id: note["id"])), absolute
    assert_includes Tensaku::Notes::Markdown.list([ note ]), "at `app/views/pages/notes.html.md:3:1-3:12`"
  end

  test "list_notes offers the archive as a status and lists it" do
    status = rpc("tools/list").dig("result", "tools").find { it["name"] == "list_notes" }.dig("inputSchema", "properties", "status")
    assert_includes status["enum"], "archived"

    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section")
    tool("start_note", id: note["id"])
    tool("resolve_note", id: note["id"], reply: "Renamed")
    Tensaku::Notes.prune!(now: Time.now + Tensaku.config.archive_after + 60)

    assert_equal "No notes.", text(tool("list_notes", status: "all"))
    assert_includes text(tool("list_notes", status: "archived")), note["id"]
  end

  test "notes link to the page at the address the browser last used" do
    Tensaku::Notes.create(url: "/about", comment: "Rename this section")
    assert_includes text(tool("list_notes")), "on /about"

    Tensaku::Project.base_url = "https://shop-signup.localhost"
    assert_includes text(tool("list_notes")), "on https://shop-signup.localhost/about"
  end

  test "the agent's name goes on the notes it starts and the messages it writes" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section")
    initialize_as("Claude Code")

    tool("start_note", id: note["id"])
    tool("reply_to_note", id: note["id"], message: "Renaming it to About")

    saved = Tensaku::Notes.find(note["id"])
    label = "Claude Code · #{Tensaku::Agents.handle(@server.session.id)}"
    assert_equal [ "working", label ], saved.values_at("status", "agent")
    assert_equal [ [ "agent", label, "Renaming it to About" ] ], saved["thread"].map { it.values_at("from", "agent", "text") }
    assert_includes text(tool("list_notes")), "#{note["id"]} (working)"
  end

  test "start_note refuses a note another running session owns, in any status, and frees it once that session is gone" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section")
    other_output = Output.new
    other = Tensaku::Mcp.new([ tmp_root ], output: other_output)
    initialize_as("Codex", server: other, output: other_output)
    initialize_as("Claude Code")

    assert_not tool_on(other, other_output, "start_note", id: note["id"])["isError"]
    assert_not tool_on(other, other_output, "start_note", id: note["id"])["isError"], "the same session can start it again"
    taken = tool("start_note", id: note["id"])
    assert taken["isError"]
    assert_includes text(taken), "Note #{note["id"]} belongs to Codex · #{Tensaku::Agents.handle(other.session.id)}"

    tool_on(other, other_output, "resolve_note", id: note["id"], reply: "Done")
    assert tool("start_note", id: note["id"])["isError"], "a resolved note still belongs to its session"
    assert tool("resolve_note", id: note["id"], reply: "Me too")["isError"]

    Tensaku::Agents.gone!(other.session.id)
    assert_not tool("start_note", id: note["id"])["isError"]
    assert_equal [ @server.session.id, "Claude Code · #{Tensaku::Agents.handle(@server.session.id)}" ], Tensaku::Notes.find(note["id"]).values_at("session", "agent")
  end

  test "watch_notes returns a note saved while it waits, and shows the agent as listening meanwhile" do
    initialize_as("Codex")
    listening = nil
    Thread.new do
      sleep 0.3
      listening = Tensaku::Agents.list.select { it["listening"] }.map { it["name"] }
      Tensaku::Notes.create(url: "/", comment: "new one")
    end

    result = tool("watch_notes", since: (Time.now.utc - 1).iso8601, timeout_seconds: 5)

    assert_includes text(result), "new one"
    assert_match(/^checked_at: \d{4}-/, text(result))
    assert_equal [ "Codex" ], listening
    assert_empty Tensaku::Agents.list.select { it["listening"] }.map { it["name"] }
    assert_equal [ "Codex" ], Tensaku::Agents.list.map { it["name"] }, "still connected"
  end

  test "watch_notes passes each note on once: checked_at as the next since skips what it returned" do
    Tensaku::Notes.create(url: "/", comment: "first")
    first = text(tool("watch_notes", since: (Time.now.utc - 5).iso8601, timeout_seconds: 1))
    assert_includes first, "first"

    checked_at = first[/checked_at: (\S+)/, 1]
    assert_equal "No new notes in 1s.", text(tool("watch_notes", since: checked_at, timeout_seconds: 1)).lines.first.strip
  end

  test "two watches in one session show as listening until the last one ends" do
    initialize_as("Codex")
    @server.handle(JSON.generate(jsonrpc: "2.0", id: "short", method: "tools/call", params: { name: "watch_notes", arguments: { timeout_seconds: 1 } }))
    @server.handle(JSON.generate(jsonrpc: "2.0", id: "long", method: "tools/call", params: { name: "watch_notes", arguments: { timeout_seconds: 3 } }))

    assert_equal "short", @output.pop["id"]
    assert_equal [ "Codex" ], Tensaku::Agents.list.select { it["listening"] }.map { it["name"] }
    assert_equal "long", @output.pop["id"]
    assert_empty Tensaku::Agents.list.select { it["listening"] }.map { it["name"] }
  end

  test "a cancelled watch stops waiting and stops listening, without a reply" do
    @server.handle(JSON.generate(jsonrpc: "2.0", id: "watch", method: "tools/call", params: { name: "watch_notes", arguments: { timeout_seconds: 60 } }))
    sleep 0.3
    assert_equal [ "MCP agent" ], Tensaku::Agents.list.select { it["listening"] }.map { it["name"] }

    @server.handle(JSON.generate(jsonrpc: "2.0", method: "notifications/cancelled", params: { requestId: "watch" }))
    sleep 0.1

    assert_empty Tensaku::Agents.list.select { it["listening"] }.map { it["name"] }
    assert_equal "pong", rpc("ping").then { it["result"] == {} ? "pong" : it }
    assert @output.empty?
  end

  test "while it runs the agent shows as connected, and it cleans up when stdin closes" do
    reader, writer = IO.pipe
    server = Thread.new { @server.run(reader) }
    writer.puts JSON.generate(jsonrpc: "2.0", id: 1, method: "initialize", params: { clientInfo: { name: "opencode", title: "OpenCode" } })
    @output.pop

    assert Tensaku::Agents.list.any?
    travel_to(Time.now + Tensaku::Agents::WINDOW + 1) { assert_not Tensaku::Agents.list.any? }

    writer.close
    server.join(5)
    assert_not Tensaku::Agents.list.any?
    assert_equal 0, Tensaku::Store.read { it.get_first_value("SELECT COUNT(*) FROM agents") }
  end

  test "with several apps, every app's notes are listed under its name, and changes go to the note's app" do
    shop, blog = %w[shop blog].map { tmp_root.join(it).tap(&:mkpath) }
    shop_note = Tensaku.with_root(shop) { Tensaku::Notes.create(url: "/cart", comment: "Bigger button") }
    blog_note = Tensaku.with_root(blog) { Tensaku::Notes.create(url: "/", comment: "Fix the title") }
    @server = Tensaku::Mcp.new([ shop, blog ], output: @output)

    listed = text(tool("list_notes"))
    assert_includes listed, "#{shop_note["id"]} (open) on /cart in shop"
    assert_includes listed, "#{blog_note["id"]} (open) on / in blog"

    tool("start_note", id: blog_note["id"])
    tool("resolve_note", id: blog_note["id"], reply: "Fixed")
    assert_equal "resolved", Tensaku.with_root(blog) { Tensaku::Notes.find(blog_note["id"])["status"] }
    assert_equal "open", Tensaku.with_root(shop) { Tensaku::Notes.find(shop_note["id"])["status"] }
  end

  test "a note saved while another write is in progress is sent after it commits, so watch_notes can't skip it" do
    released_at = nil
    holder = Thread.new { Tensaku::Store.write { sleep 0.3; released_at = Time.now.utc } }
    sleep 0.1

    note = Tensaku::Notes.create(url: "/", comment: "late")
    holder.join

    assert_operator Time.iso8601(note["sent_at"]), :>=, released_at
  end

  test "decline_note closes a note with the reason in its thread" do
    note = Tensaku::Notes.create(url: "/about", comment: "Make it blink")

    assert_equal "Declined note #{note["id"]}. No open notes left.", text(tool("decline_note", id: note["id"], reason: "Blinking text fails WCAG 2.3.1"))

    saved = Tensaku::Notes.find(note["id"])
    assert_equal [ "declined", "Blinking text fails WCAG 2.3.1" ], [ saved["status"], saved["thread"].last["text"] ]
    assert_equal "No notes.", text(tool("list_notes"))
  end

  test "unknown notes and tools are tool errors, not crashes" do
    assert tool("get_note", id: "zzzz")["isError"]
    assert tool("nope")["isError"]
  end

  test "lists keep only the latest part of a long thread, and get_note has all of it" do
    note = Tensaku::Notes.create(url: "/", comment: "Move the flower")
    %w[you agent you agent you].each_with_index { |from, i| Tensaku::Notes.update(note["id"], from:, message: "#{from} #{i}") }

    listed = text(tool("list_notes"))
    assert_includes listed, "Move the flower"
    assert_includes listed, "*(3 earlier messages; get_note #{note["id"]} has the whole thread)*"
    assert_equal [ "agent 3", "you 4" ], listed.scan(/(?:agent|you) \d/)

    assert_equal %w[you\ 0 agent\ 1 you\ 2 agent\ 3 you\ 4], text(tool("get_note", id: note["id"])).scan(/(?:agent|you) \d/)
  end

  test "watch_notes claims the note for its session and records the delivery, without sending it again" do
    initialize_as("Codex")
    note = Tensaku::Notes.create(url: "/", comment: "Rename")

    reply = text(tool("watch_notes", since: (Time.now.utc - 5).iso8601, timeout_seconds: 1))
    handle = Tensaku::Agents.handle(@server.session.id)
    assert_includes reply, "You are listening as Codex · #{handle}"
    assert_not_includes text(tool("watch_notes", timeout_seconds: 1)), "You are listening as", "only the first watch says it"

    saved = Tensaku::Notes.find(note["id"])
    assert_equal [ "Codex · #{handle}", @server.session.id ], saved.values_at("delivered_to", "session")
    assert saved["delivered_at"]
    assert_equal note["sent_at"], saved["sent_at"]
  end

  test "a listening agent gets notes sent while it works with its next answer, claimed, and a watch doesn't hand them over again" do
    first = Tensaku::Notes.create(url: "/", comment: "First")
    since = (Time.now.utc - 5).iso8601
    tool("watch_notes", since:, timeout_seconds: 1)
    tool("start_note", id: first["id"])

    follow_up = Tensaku::Notes.create(url: "/", comment: "Second")
    resolved = tool("resolve_note", id: first["id"], reply: "Done")

    assert_equal "Resolved note #{first["id"]}. No other open notes left.", resolved.dig("content", 0, "text")
    assert_includes resolved.dig("content", 1, "text"), "Notes the person saved while you worked. They are yours and already started"
    assert_includes resolved.dig("content", 1, "text"), "## Tensaku note #{follow_up["id"]} (working)"
    assert_equal @server.session.id, Tensaku::Notes.find(follow_up["id"])["session"]

    assert_equal 1, tool("reply_to_note", id: follow_up["id"], message: "On it")["content"].size
    assert_not_includes text(tool("watch_notes", since:, timeout_seconds: 1)), follow_up["id"], "a watch with an older since doesn't repeat it"
  end

  test "an agent that never listened only hears the ids of notes sent since it last looked" do
    tool("list_notes")
    note = Tensaku::Notes.create(url: "/", comment: "Second")
    reply = tool("get_note", id: note["id"])

    assert_equal "1 note was saved on the page since you last looked (#{note["id"]}). Call watch_notes or list_notes next.", reply.dig("content", 1, "text")
    assert_nil Tensaku::Notes.find(note["id"])["session"]
  end

  test "each tool call is logged with its duration, answer size and the notes it handed over" do
    initialize_as("Codex")
    note = Tensaku::Notes.create(url: "/", comment: "Rename")
    tool("watch_notes", since: (Time.now.utc - 5).iso8601, timeout_seconds: 1)
    tool("get_note", id: "zzzz")

    lines = tmp_root.join("tmp/tensaku/mcp.log").readlines.map { JSON.parse(it) }
    assert_equal %w[watch_notes get_note], lines.map { it["tool"] }
    assert_equal [ note["id"] ], lines.first["notes"]
    assert_equal [ Tensaku::Agents.handle(@server.session.id), "Codex" ], lines.first.values_at("session", "agent")
    assert lines.all? { it["ms"].is_a?(Integer) && it["bytes"].positive? }
    assert lines.last["error"]
  end

  test "the page gets each agent's folder, start time, last call and the notes it works on" do
    note = Tensaku::Notes.create(url: "/about", comment: "Rename this section")
    initialize_as("Claude Code")
    tool("start_note", id: note["id"])

    agent = Tensaku::Agents.list.sole
    assert_equal "Claude Code", agent["name"]
    assert_equal "#{Pathname(Dir.pwd).basename}/", agent["folder"]
    assert Time.iso8601(agent["started_at"])
    assert_equal({ "tool" => "start_note", "note" => note["id"] }, agent["last"].except("at"))
    assert_equal [ { "id" => note["id"], "url" => "/about", "comment" => "Rename this section" } ], agent["working"]
  end

  test "two sessions watching at once get each note once" do
    other_output = Output.new
    other = Tensaku::Mcp.new([ tmp_root ], output: other_output)
    initialize_as("Codex", server: other, output: other_output)
    initialize_as("Claude Code")
    since = (Time.now.utc - 5).iso8601
    notes = 6.times.map { Tensaku::Notes.create(url: "/", comment: "Note #{it}") }

    replies = [ [ @server, @output ], [ other, other_output ] ].map do |server, output|
      Thread.new { text(tool_on(server, output, "watch_notes", since:, timeout_seconds: 1)) }
    end.map(&:value)

    ids = notes.map { it["id"] }
    got = replies.map { |reply| ids.select { reply.include?(it) } }
    assert_equal ids.sort, got.flatten.sort, "every note reached one session, none reached both"
    got.zip([ @server, other ]).each { |found, server| found.each { assert_equal server.session.id, Tensaku::Notes.find(it)["session"] } }
  end

  test "a request for changes goes back to the session that owns the note, and to anyone once it is gone" do
    other_output = Output.new
    other = Tensaku::Mcp.new([ tmp_root ], output: other_output)
    initialize_as("Codex", server: other, output: other_output)
    initialize_as("Claude Code")
    note = Tensaku::Notes.create(url: "/", comment: "Rename")
    since = (Time.now.utc - 5).iso8601
    tool_on(other, other_output, "watch_notes", since:, timeout_seconds: 1)
    tool_on(other, other_output, "resolve_note", id: note["id"], reply: "Renamed")

    Tensaku::Notes.update(note["id"], status: "open", from: "you", message: "Shorter", send: true)
    assert_not_includes text(tool("watch_notes", since:, timeout_seconds: 1)), note["id"]
    assert_not_includes text(tool("list_notes")), note["id"]
    assert_includes text(tool_on(other, other_output, "watch_notes", since:, timeout_seconds: 1)), note["id"]

    Tensaku::Agents.gone!(other.session.id)
    Tensaku::Notes.update(note["id"], status: "open", from: "you", message: "Shorter still", send: true)
    assert_includes text(tool("watch_notes", since:, timeout_seconds: 1)), note["id"]
    assert_equal @server.session.id, Tensaku::Notes.find(note["id"])["session"]
  end

  test "in Claude Code, a channel that answers the hello gets each saved note pushed and claimed" do
    init = initialize_as("Claude Code")
    assert_equal({}, init.dig("result", "capabilities", "experimental", "claude/channel"))
    assert_includes init.dig("result", "instructions"), "channel_ready"
    @server.handle(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))
    hello = @output.pop
    assert_equal "notifications/claude/channel", hello["method"]
    assert_equal "hello", hello.dig("params", "meta", "kind")
    code = hello.dig("params", "content")[/code (\w+)/, 1]

    assert tool("channel_ready", code: "wrong")["isError"]
    assert_includes text(tool("channel_ready", code:)), "channel works"
    assert_equal [ [ true, true ] ], Tensaku::Agents.list.map { it.values_at("channel", "listening") }

    note = Tensaku::Notes.create(url: "/about", comment: "Bigger title")
    pushed = @output.pop(timeout: 5)
    assert_equal "notifications/claude/channel", pushed["method"]
    assert_equal({ "kind" => "notes", "notes" => note["id"] }, pushed.dig("params", "meta"))
    assert_includes pushed.dig("params", "content"), "Bigger title"
    assert_equal @server.session.id, Tensaku::Notes.find(note["id"])["session"]

    # Answering the agent's question makes the note new again: it comes back to this session.
    tool("ask_question", id: note["id"], question: "How big?")
    Tensaku::Notes.update(note["id"], from: "you", message: "Twice as big", status: "open", send: true)
    assert_includes @output.pop(timeout: 5).dig("params", "content"), "Twice as big"
  end

  test "other clients get no channel capability and no hello" do
    init = initialize_as("Codex")
    assert_nil init.dig("result", "capabilities", "experimental")
    @server.handle(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))
    sleep 0.1
    assert @output.empty?
  end

  test "a note whose session ended mid-work is listed as nobody's, and can be taken over" do
    note = Tensaku::Notes.create(url: "/", comment: "Half done")
    Tensaku::Notes.start(note["id"], agent: "Codex · gone-fox", session: SecureRandom.hex(16))

    assert_includes text(tool("list_notes")), "Its session stopped while working on it, so it is nobody's now"
    assert_not tool("start_note", id: note["id"])["isError"]
  end

  test "a note sent to one session goes to it alone, even while it is busy and another session is idle" do
    other_output = Output.new
    other = Tensaku::Mcp.new([ tmp_root ], output: other_output)
    initialize_as("Codex", server: other, output: other_output)
    initialize_as("Claude Code")
    since = (Time.now.utc - 5).iso8601
    tool_on(other, other_output, "start_note", id: Tensaku::Notes.create(url: "/", comment: "Busy with this")["id"])
    handle = Tensaku::Agents.handle(other.session.id)

    note = Tensaku::Notes.create(url: "/", comment: "For Codex", to: handle)
    assert_equal "Codex · #{handle}", note["agent"]
    assert_not_includes text(tool("watch_notes", since:, timeout_seconds: 1)), note["id"]
    assert_includes text(tool("list_notes")), "2 more notes belong to other running agent sessions"
    assert tool("start_note", id: note["id"])["isError"]
    Tensaku::Agents.seen!(@server.session.id, name: "Claude Code", listening: true)
    reply = text(tool_on(other, other_output, "watch_notes", since:, timeout_seconds: 1))
    assert_includes reply, note["id"]
    assert_includes reply, "*Yours, and started: make the change, then resolve it.*"

    assert_raises(Tensaku::Error) { Tensaku::Notes.create(url: "/", comment: "Nobody", to: "gone-fox") }
  end

  test "the page can assign a note to another session or to anyone, and take one back mid-work" do
    other_output = Output.new
    other = Tensaku::Mcp.new([ tmp_root ], output: other_output)
    initialize_as("Codex", server: other, output: other_output)
    initialize_as("Claude Code")
    since = (Time.now.utc - 5).iso8601
    note = Tensaku::Notes.create(url: "/", comment: "Rename", to: Tensaku::Agents.handle(other.session.id))

    Tensaku::Notes.update(note["id"], from: "you", to: Tensaku::Agents.handle(@server.session.id))
    assert_includes text(tool("watch_notes", since:, timeout_seconds: 1)), note["id"]
    assert_equal @server.session.id, Tensaku::Notes.find(note["id"])["session"]

    Tensaku::Notes.update(note["id"], from: "you", to: "")
    assert_includes text(tool("list_notes")), "*Nobody's yet: call start_note"
    tool("start_note", id: note["id"])
    # Taken back mid-work: open again, and this session can't resolve it.
    Tensaku::Notes.update(note["id"], from: "you", to: "")
    assert_equal "open", Tensaku::Notes.find(note["id"])["status"]
    assert tool("resolve_note", id: note["id"], reply: "Done")["isError"]

    tool("start_note", id: note["id"])
    tool("resolve_note", id: note["id"], reply: "Done")
    assert_raises(Tensaku::Error) { Tensaku::Notes.update(note["id"], from: "you", to: "") }
  end

  test "a session whose process runs keeps its notes when its check-ins are late" do
    initialize_as("Claude Code")
    note = Tensaku::Notes.create(url: "/", comment: "Rename")
    tool("start_note", id: note["id"])
    Tensaku::Store.write { it.execute("UPDATE agents SET seen_at = ?", [ Time.now.to_f - 600 ]) }

    assert_not Tensaku::Notes.available_to?(Tensaku::Notes.find(note["id"]), SecureRandom.hex(16))
    assert_empty Tensaku::Agents.list, "the page doesn't list it as connected"
  end

  test "each session has a two word handle, kept with the agent and given to the page" do
    initialize_as("Claude Code")
    handle = Tensaku::Agents.handle(@server.session.id)

    assert_match(/\A[a-z]+-[a-z]+\z/, handle)
    assert_equal handle, Tensaku::Agents.handle(@server.session.id)
    assert_equal handle, Tensaku::Store.read { it.get_first_value("SELECT handle FROM agents WHERE session = ?", [ @server.session.id ]) }
    assert_equal [ handle ], Tensaku::Agents.list.map { it["handle"] }
  end

  test "the dev server has no MCP endpoint" do
    response = Rack::MockRequest.new(Rails.application).post("/__tensaku/mcp",
      "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost:3000", "HTTP_X_TENSAKU_TOKEN" => Tensaku.token, input: "{}")
    assert_equal 404, response.status
  end
end
