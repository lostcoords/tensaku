require "test_helper"

# Concurrent writers, hand-edited note files and the watch_notes timing.
class Tensaku::WriteSafetyTest < Tensaku::TestCase
  setup { Tensaku.root = tmp_root }
  teardown { Tensaku.root = nil }

  test "concurrent changes to one note all land" do
    note = Tensaku::Notes.create(url: "/", comment: "Fix this")

    Array.new(8) { |index| Thread.new { Tensaku::Notes.update(note["id"], message: "Message #{index}", from: "agent") } }.each(&:join)

    assert_equal 8, Tensaku::Notes.find(note["id"])["thread"].size
    assert_empty Tensaku::Notes.dir.glob(".*.tmp")
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

  test "a malformed note file is skipped instead of breaking the list" do
    Tensaku::Notes.create(url: "/", comment: "Good")
    Tensaku::Notes.dir.join("bad1.json").write("[1, 2]")
    Tensaku::Notes.dir.join("bad2.json").write(JSON.generate(id: "bad2", comment: "No dates"))

    assert_equal [ "Good" ], Tensaku::Notes.list.map { it["comment"] }
    assert_raises(Tensaku::Notes::NotFound) { Tensaku::Notes.find("bad2") }
  end

  test "watch sees a note saved in the same second as since" do
    since = Time.now.utc
    note = Tensaku::Notes.create(url: "/", comment: "Right away")

    notes, checked_at = Tensaku::Notes.watch(since:, timeout: 1)

    assert_equal [ note["id"] ], notes.map { it["id"] }
    assert_operator checked_at, :>, since
  end

  test "the selection is shared through a file" do
    Tensaku::Notes.selection = { "url" => "/about" }

    assert_equal "/about", Tensaku::Notes.selection["url"]
  end
end
