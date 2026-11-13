require "test_helper"

# Concurrent writers, in threads and in processes, and the watch_notes timing.
class Tensaku::WriteSafetyTest < Tensaku::TestCase
  setup { Tensaku.root = tmp_root }
  teardown { Tensaku.root = nil }

  test "concurrent changes to one note all land" do
    note = Tensaku::Notes.create(url: "/", comment: "Fix this")

    Array.new(8) { |index| Thread.new { Tensaku::Notes.update(note["id"], message: "Message #{index}", from: "agent") } }.each(&:join)

    assert_equal 8, Tensaku::Notes.find(note["id"])["thread"].size
  end

  test "two processes claiming at once get each note once" do
    notes = 20.times.map { Tensaku::Notes.create(url: "/", comment: "Note #{it}") }
    since = Time.now.utc - 60
    Tensaku::Store.reset!
    # Both stay running until both have claimed: a note whose owner's process is gone is free again.
    done_reader, done_writer = IO.pipe
    children = 2.times.map do |i|
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        done_writer.close
        session = SecureRandom.hex(16)
        Tensaku::Agents.seen!(session, name: "Agent #{i}", listening: true)
        claimed = Tensaku::Notes.claim_sent(since, Time.now.utc, session:, agent: "Agent #{i}")
        writer.puts(JSON.generate(claimed.map { it["id"] }))
        writer.flush
        done_reader.read
        exit!(0)
      end
      writer.close
      [ pid, reader ]
    end
    claimed = children.map { |_, reader| JSON.parse(reader.gets) }
    done_writer.close
    children.each { |pid, _| Process.wait(pid) }

    assert_equal notes.map { it["id"] }.sort, claimed.flatten.sort
  end

  test "concurrent template saves don't overwrite each other" do
    tmp_root.join("app/views/pages").mkpath
    view = tmp_root.join("app/views/pages/list.html.erb")
    view.write(%(<ul>\n  <li>One</li>\n  <li>Two</li>\n</ul>\n))

    edits = [ [ 2, "Uno" ], [ 3, "Dos" ] ].map do |line, text|
      piece = Tensaku::Source::Template.new("app/views/pages/list.html.erb").describe(line, 3)[:pieces].first
      { stamp: "app/views/pages/list.html.erb:#{line}:3", edits: [ { start: piece[:start], end: piece[:end], original: piece[:raw], text: } ] }
    end
    headers = { "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost", "CONTENT_TYPE" => "application/json", "HTTP_X_TENSAKU_TOKEN" => Tensaku.token }
    statuses = edits.map do |edit|
      Thread.new { Rack::MockRequest.new(Rails.application).post("/__tensaku/text", headers.merge(input: JSON.generate(edit))).status }
    end.map(&:value)

    assert_equal [ 200, 200 ], statuses
    assert_equal %(<ul>\n  <li>Uno</li>\n  <li>Dos</li>\n</ul>\n), view.read
  end

  test "sent_between sees a note saved in the same second as since, and not one sent after upto" do
    since = Time.now.utc
    note = Tensaku::Notes.create(url: "/", comment: "Right away")
    upto = Time.now.utc
    Tensaku::Notes.create(url: "/", comment: "Later")

    assert_equal [ note["id"] ], Tensaku::Notes.sent_between(since, upto).map { it["id"] }
  end

  test "each tab keeps its own selection, and the newest is the one an agent gets" do
    Tensaku::Project.select!({ "url" => "/about" }, tab: "one")
    Tensaku::Project.select!({ "url" => "/blog" }, tab: "two")
    Tensaku::Project.select!({ "url" => "/contact" }, tab: "one")

    assert_equal "/contact", Tensaku::Project.selection["url"]
    assert_equal 2, Tensaku::Store.read { it.get_first_value("SELECT COUNT(*) FROM selections") }
  end
end
