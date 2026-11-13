require "test_helper"
require "open3"
require "tensaku/cli"

# `tensaku mcp` runs as its own process, without Rails, started by the agent.
class Tensaku::CliTest < Tensaku::TestCase
  EXE = File.expand_path("../../exe/tensaku", __dir__)

  def app(path, gemfile_lock: "    tensaku (0.1.0)\n")
    root = tmp_root.join(path)
    root.join("config").mkpath
    root.join("config/application.rb").write("")
    root.join("Gemfile.lock").write(gemfile_lock) if gemfile_lock
    root
  end

  test "serves the app that contains the current directory, from any directory inside it" do
    shop = app("shop")
    shop.join("app/views").mkpath

    assert_equal [ shop ], Tensaku::CLI.apps([], pwd: shop.join("app/views"))
    assert_equal [ shop ], Tensaku::CLI.apps([], pwd: shop)
  end

  test "outside an app, serves the apps below that use tensaku, skipping tests, dependencies and other apps" do
    docs = app("docs")
    admin = app("apps/admin")
    app("apps/other", gemfile_lock: "    rails (8.1.0)\n")
    app("test/dummy")
    app("node_modules/pkg")
    app("a/b/too_deep")

    assert_equal [ admin, docs ], Tensaku::CLI.apps([], pwd: tmp_root)
  end

  test "--app picks the apps, relative to the current directory" do
    shop = app("shop")
    blog = app("blog", gemfile_lock: nil)

    assert_equal [ shop, blog ], Tensaku::CLI.apps([ "--app", "shop", "--app", blog.to_s ], pwd: tmp_root)
  end

  test "tensaku mcp answers over stdio without Rails, shows the agent while it runs, and cleans up" do
    shop = app("shop")
    Tensaku.with_root(shop) { Tensaku::Notes.create(url: "/cart", comment: "Bigger button") }

    Open3.popen3(RbConfig.ruby, EXE, "mcp", chdir: shop.to_s) do |stdin, stdout, stderr, wait|
      stdin.puts JSON.generate(jsonrpc: "2.0", id: 1, method: "initialize", params: { clientInfo: { name: "codex", title: "Codex" } })
      assert_equal "tensaku", JSON.parse(stdout.gets).dig("result", "serverInfo", "name")
      stdin.puts JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "list_notes", arguments: {} })
      assert_includes JSON.parse(stdout.gets).dig("result", "content", 0, "text"), "Bigger button"
      assert_equal [ "Codex" ], Tensaku.with_root(shop) { Tensaku::Agents.list.map { it["name"] } }
      stdin.puts JSON.generate(jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "get_note", arguments: { id: "rails" } })
      assert JSON.parse(stdout.gets).dig("result", "isError")

      stdin.close
      assert wait.value.success?, stderr.read
    end
    assert_equal 0, Tensaku::Store.read { it.get_first_value("SELECT COUNT(*) FROM agents") }
  end

  test "tensaku notes lists, starts and resolves notes like the MCP tools, as a session that leaves when done" do
    shop = app("shop")
    note = Tensaku.with_root(shop) { Tensaku::Notes.create(url: "/cart", comment: "Bigger button") }
    run = ->(*args) { Open3.capture3(RbConfig.ruby, EXE, "notes", *args, chdir: shop.to_s) }

    listed, = run.call
    assert_includes listed, "## Tensaku note #{note["id"]} (open) on /cart"
    started, = run.call("start", note["id"], "--as", "Aider")
    assert_match(/Started note #{note["id"]}\. The page shows you as Aider · [a-z]+-[a-z]+\./, started)
    resolved, = run.call("resolve", note["id"], "Made", "it", "bigger")
    assert_includes resolved, "Resolved note #{note["id"]}."

    saved = Tensaku.with_root(shop) { Tensaku::Notes.find(note["id"]) }
    assert_equal [ "resolved", "Made it bigger" ], [ saved["status"], saved["thread"].last["text"] ]
    assert_equal 0, Tensaku::Store.read { it.get_first_value("SELECT COUNT(*) FROM agents") }

    _, _, status = run.call("show", "zzzz")
    assert_not status.success?
    usage, = run.call("frobnicate")
    assert_includes usage, "tensaku notes resolve ID REPLY"
  end

  test "tensaku mcp without an app says so, and other commands print the usage" do
    _, error, status = Open3.capture3(RbConfig.ruby, EXE, "mcp", chdir: tmp_root.to_s)
    assert_not status.success?
    assert_match "no Rails app with tensaku found", error

    output, = Open3.capture3(RbConfig.ruby, EXE, "claude")
    assert_match "Usage: bundle exec tensaku mcp", output
  end
end
