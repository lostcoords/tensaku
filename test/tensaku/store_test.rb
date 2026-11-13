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

  test "a heartbeat with nothing new isn't a change" do
    session = SecureRandom.hex(16)
    Tensaku::Agents.seen!(session, name: "Codex")
    before = Tensaku::Project.version
    Tensaku::Agents.seen!(session, name: "Codex")
    assert_equal before, Tensaku::Project.version
    assert Tensaku::Agents.connected?(session)
  end

  test "a session is connected while its process holds its lock, and not once the process ends, whatever its pid" do
    session = SecureRandom.hex(16)
    Tensaku::Store.reset!
    reader, writer = IO.pipe
    child = fork do
      reader.close
      Tensaku::Agents.seen!(session, name: "Codex")
      writer.puts "ready"
      writer.flush
      sleep
    end
    writer.close
    reader.gets
    assert Tensaku::Agents.connected?(session)
    assert_equal [ "Codex" ], Tensaku::Agents.list.map { it["name"] }

    Process.kill(:KILL, child)
    Process.wait(child)
    # The row still names the dead process's pid, which the system may give to a new process.
    Tensaku::Store.write { it.execute("UPDATE agents SET pid = ?", [ Process.pid ]) }
    assert_not Tensaku::Agents.connected?(session)
    assert_empty Tensaku::Agents.list
    assert_not Tensaku::Presence.path(session).exist?, "the free lock file is cleaned up"
  end

  test "an agent that started before Tensaku's code changed is marked outdated" do
    Tensaku::Agents.seen!(SecureRandom.hex(16), name: "Current")
    Tensaku::Agents.seen!(SecureRandom.hex(16), name: "Old", version: "000000000000")

    assert_equal({ "Current" => false, "Old" => true }, Tensaku::Agents.list.to_h { [ it["name"], it["outdated"] ] })
  end

  test "a database at an older schema version gets the later migrations" do
    Tensaku::Store.reset!
    path = Tensaku::Store.path
    path.dirname.mkpath
    old = SQLite3::Database.new(path.to_s)
    old.execute_batch(Tensaku::Store::SCHEMA)
    old.execute("PRAGMA user_version = 2")
    old.close

    Tensaku::Agents.seen!(SecureRandom.hex(16), name: "Codex")
    assert_equal Tensaku::Store::VERSION, Tensaku::Store.read { it.get_first_value("PRAGMA user_version") }
    assert Tensaku::Store.read { it.execute("PRAGMA table_info(agents)").any? { it["name"] == "version" } }
  end

  test "a new session gets a handle no connected session of the app has" do
    first = SecureRandom.hex(16)
    second = first[0, 4] + SecureRandom.hex(14)
    Tensaku::Agents.seen!(first, name: "Codex")

    assert_equal Tensaku::Agents.handle(first), Tensaku::Agents.handle(second)
    assert_not_equal Tensaku::Agents.handle(first), Tensaku::Agents.free_handle(second)
    assert_equal Tensaku::Agents.handle(second, 1), Tensaku::Agents.free_handle(second)
  end

  test "a session busy with a note leaves new ones to an idle listener, and takes them when nobody is idle" do
    busy, idle = 2.times.map { SecureRandom.hex(16) }
    Tensaku::Agents.seen!(busy, name: "Busy", listening: true)
    Tensaku::Agents.seen!(idle, name: "Idle", listening: true)
    Tensaku::Notes.start(Tensaku::Notes.create(url: "/", comment: "Working on it")["id"], agent: "Busy", session: busy)
    since = Time.now.utc
    note = Tensaku::Notes.create(url: "/", comment: "New")

    assert_empty Tensaku::Notes.claim_sent(since, Time.now.utc, session: busy, agent: "Busy")
    Tensaku::Agents.seen!(idle, name: "Idle", listening: false)
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
