require "test_helper"

# The database, the doorbell that wakes its readers, and the rules for agents and the archive.
class Tensaku::StoreTest < Tensaku::TestCase
  setup { Tensaku.root = tmp_root }
  teardown { Tensaku.root = nil }

  test "the database lives in TENSAKU_HOME, and each app sees only its own notes" do
    shop, blog = %w[shop blog].map { tmp_root.join(it).tap(&:mkpath) }
    Tensaku.with_root(shop) { Tensaku::Notes.create(url: "/", comment: "Shop note") }
    Tensaku.with_root(blog) { Tensaku::Notes.create(url: "/", comment: "Blog note") }

    assert Pathname(ENV["TENSAKU_HOME"]).join("tensaku.sqlite3").file?
    assert_equal "700", format("%o", File.stat(ENV["TENSAKU_HOME"]).mode & 0o777)
    assert_equal [ "Shop note" ], Tensaku.with_root(shop) { Tensaku::Notes.all.map { it["comment"] } }
    assert_equal [ "Blog note" ], Tensaku.with_root(blog) { Tensaku::Notes.all.map { it["comment"] } }
  end

  test "the data folder follows each platform's convention" do
    with_env("TENSAKU_HOME" => nil, "XDG_DATA_HOME" => "/data") do
      expected = RUBY_PLATFORM.include?("darwin") ? File.join(Dir.home, "Library", "Application Support", "tensaku") : "/data/tensaku"
      assert_equal expected, Tensaku.home.to_s
    end
  end

  test "a note records the commit it was written against" do
    tmp_root.join(".git/refs/heads").mkpath
    tmp_root.join(".git/HEAD").write("ref: refs/heads/main\n")
    tmp_root.join(".git/refs/heads/main").write("#{"a" * 40}\n")
    tmp_root.join(".git/config").write(%([remote "origin"]\n\turl = git@example.com:me/shop.git\n))

    assert_equal "a" * 40, Tensaku::Notes.create(url: "/", comment: "Here")["commit"]
    assert_equal "git@example.com:me/shop.git", Tensaku::Repo.remote(tmp_root)
  end

  test "a write wakes a reader waiting on the doorbell right away, and a dead socket is removed" do
    Tensaku::Notes.create(url: "/", comment: "Opens the database first")
    Tensaku::Doorbell.listen(tmp_root) do |doorbell|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      writer = Thread.new { sleep 0.05; Tensaku::Notes.create(url: "/", comment: "Ring") }
      assert doorbell.wait(5)
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5
      writer.join
      assert_not doorbell.wait(0.1), "nothing else rang"
    end

    folder = Tensaku::Doorbell.dir(tmp_root)
    dead = folder.join("1-dead.sock")
    UNIXServer.new(dead.to_s).close
    Tensaku::Notes.create(url: "/", comment: "Ring again")
    assert_not dead.exist?
  end

  test "a heartbeat with nothing new isn't a change, and an agent whose process is gone isn't connected" do
    session = SecureRandom.hex(16)
    Tensaku::Notes.agent_seen!(session, name: "Codex", pid: Process.pid)
    before = Tensaku::Notes.version
    Tensaku::Notes.agent_seen!(session, name: "Codex", pid: Process.pid)
    assert_equal before, Tensaku::Notes.version
    assert Tensaku::Notes.agent_connected?(session)

    gone = Process.spawn(RbConfig.ruby, "-e", "exit").tap { Process.wait(it) }
    Tensaku::Notes.agent_seen!(session, name: "Codex", pid: gone)
    assert_not Tensaku::Notes.agent_connected?(session)
    assert_empty Tensaku::Notes.agents
  end

  test "a new session gets a handle no connected session of the app has" do
    first = SecureRandom.hex(16)
    second = first[0, 4] + SecureRandom.hex(14)
    Tensaku::Notes.agent_seen!(first, name: "Codex")

    assert_equal Tensaku::Notes.handle(first), Tensaku::Notes.handle(second)
    assert_not_equal Tensaku::Notes.handle(first), Tensaku::Notes.free_handle(second)
    assert_equal Tensaku::Notes.handle(second, 1), Tensaku::Notes.free_handle(second)
  end

  test "a session busy with a note leaves new ones to an idle listener, and takes them when nobody is idle" do
    busy, idle = 2.times.map { SecureRandom.hex(16) }
    Tensaku::Notes.agent_seen!(busy, name: "Busy", listening: true)
    Tensaku::Notes.agent_seen!(idle, name: "Idle", listening: true)
    Tensaku::Notes.start(Tensaku::Notes.create(url: "/", comment: "Working on it")["id"], agent: "Busy", session: busy)
    since = Time.now.utc
    note = Tensaku::Notes.create(url: "/", comment: "New")

    assert_empty Tensaku::Notes.claim_sent(since, Time.now.utc, session: busy, agent: "Busy")
    Tensaku::Notes.agent_seen!(idle, name: "Idle", listening: false)
    assert_equal [ note["id"] ], Tensaku::Notes.claim_sent(since, Time.now.utc, session: busy, agent: "Busy").map { it["id"] }
  end

  test "closed notes move to the archive after archive_after, stay listable, and come back when reopened" do
    note = Tensaku::Notes.create(url: "/", comment: "Old")
    Tensaku::Notes.update(note["id"], status: "resolved", message: "Done")
    open = Tensaku::Notes.create(url: "/", comment: "Still open")

    Tensaku::Notes.prune!(now: Time.now + Tensaku.config.archive_after + 60)

    assert_equal [ open["id"] ], Tensaku::Notes.all.map { it["id"] }
    assert_equal [ note["id"] ], Tensaku::Notes.list(status: "archived").map { it["id"] }
    Tensaku::Notes.update(note["id"], status: "open", from: "you", message: "Not quite", send: true)
    assert_equal [ note["id"], open["id"] ].sort, Tensaku::Notes.all.map { it["id"] }.sort
  end

  def with_env(values)
    old = values.keys.to_h { [ it, ENV[it] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    old.each { |key, value| ENV[key] = value }
  end
end
