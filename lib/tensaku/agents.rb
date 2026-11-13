require "json"

module Tensaku
  # The agent sessions connected to the app at Tensaku.root. Each `tensaku mcp` process (Session)
  # checks in every few seconds while it runs, and the page reads the rows to say who is connected and
  # what each is doing. A session owns the notes it was handed or started while its process runs
  # (Presence), so two sessions never change the same thing.
  module Agents
    # An agent counts as connected for this long after its process last checked in.
    WINDOW = 20
    SESSION = /\A[a-f0-9]{32}\z/
    COLUMNS = %w[name handle listening cwd pid started_at last version channel].freeze

    HANDLE_WORDS = [
      %w[amber brisk calm dusky eager fern gilded hazy ivory jolly keen lucid misty noble olive plum quiet rosy sandy tidy umber vivid wary young zesty bold coral dewy frosty grassy lemon mossy],
      %w[fox heron otter lynx wren badger crane finch gecko hare ibis koala lark mole newt owl panda quail raven seal tern vole wolf yak bison camel dingo egret ferret moth stoat toad]
    ].freeze

    module_function

    # A check-in: the client's name, its handle, the directory it runs in, when it started, whether a
    # watch_notes call is waiting, whether notes are pushed over a Claude Code channel, its last tool
    # call ({ "tool", "note", "at" }), and the fingerprint of the code it runs (Build). A check-in with
    # nothing new isn't a change.
    def seen!(session, name:, handle: nil, listening: false, channel: false, cwd: nil, started_at: nil, last: nil, version: Build.started)
      Presence.hold(session)
      row = [ name.to_s, (handle || self.handle(session)).to_s, listening ? 1 : 0, cwd, Process.pid, started_at, last && JSON.generate(last), version, channel ? 1 : 0 ]
      Project.write do |db, app|
        before = db.get_first_row("SELECT #{COLUMNS.join(", ")}, seen_at FROM agents WHERE session = ? AND project = ?", [ session, app ])
        db.execute(<<~SQL, [ session, app, *row, Time.now.to_f ])
          INSERT INTO agents (session, project, #{COLUMNS.join(", ")}, seen_at) VALUES (?, ?, #{(%w[?] * COLUMNS.size).join(", ")}, ?)
          ON CONFLICT (session, project) DO UPDATE SET #{(COLUMNS + %w[seen_at]).map { "#{it} = excluded.#{it}" }.join(", ")}
        SQL
        reconnected = before && before["seen_at"] < Time.now.to_f - WINDOW
        Project.changed!(db, app, "agent") if before.nil? || reconnected || before.values_at(*COLUMNS) != row
      end
    end

    def gone!(session)
      Project.write do |db, app|
        Presence.release(session)
        db.execute("DELETE FROM agents WHERE session = ? AND project = ?", [ session.to_s, app ])
        Project.changed!(db, app, "agent") if db.changes.positive?
      end
    end

    # Whether session still owns its notes: its process is running. A late check-in (a database busy for
    # a while, a suspended laptop) doesn't free a note an agent is working on; a crashed or closed agent
    # frees it at once.
    def connected?(session)
      return false unless session.to_s.match?(SESSION)

      Project.read do |db, app|
        db.get_first_value("SELECT 1 FROM agents WHERE session = ? AND project = ?", [ session.to_s, app ]) && Presence.alive?(session)
      end
    end

    # The sessions that checked in lately and whose process still runs.
    def connected_sessions(db, app, now: Time.now)
      db.execute("SELECT session FROM agents WHERE project = ? AND seen_at > ?", [ app, now.to_f - WINDOW ])
        .map { it["session"] }.select { Presence.alive?(it) }
    end

    # The agents connected to this app, oldest first, as the page shows them: name, handle, the
    # directory it runs in, when it started, whether it is listening, its last tool call, and the notes
    # it is working on.
    def list(now: Time.now)
      working = Notes.all.select { it["status"] == "working" }.group_by { it["session"] }
      rows = Project.read { |db, app| db.execute("SELECT * FROM agents WHERE project = ? AND seen_at > ?", [ app, now.to_f - WINDOW ]) }
      rows.select { Presence.alive?(it["session"]) }.map do |row|
        last = row["last"] && JSON.parse(row["last"])
        {
          "name" => row["name"].presence || "MCP agent",
          "handle" => row["handle"],
          "folder" => folder(row["cwd"]),
          "started_at" => row["started_at"],
          "listening" => row["listening"] == 1,
          # Notes are pushed into the session over a Claude Code channel (see Session).
          "channel" => row["channel"] == 1,
          "last" => last.is_a?(Hash) ? last.slice("tool", "note", "at") : nil,
          # Started before Tensaku's code last changed: it should reconnect to run the new code.
          "outdated" => row["version"] != Build.current,
          "working" => Array(working[row["session"]]).map { { "id" => it["id"], "url" => it["url"], "comment" => it["comment"].to_s.squish.truncate(80) } }
        }.compact
      end.sort_by { [ it["started_at"].to_s, it["name"] ] }
    end

    # The owner fields of a note for the connected session whose handle is handle: that session alone
    # gets it, as if it had claimed it. Blank means any agent.
    def owner(db, app, handle)
      return {} if handle.blank?

      row = db.execute("SELECT session, name, handle FROM agents WHERE project = ? AND handle = ? AND seen_at > ?", [ app, handle.to_s, Time.now.to_f - WINDOW ])
        .find { Presence.alive?(it["session"]) }
      raise Error, "#{handle} isn't connected any more. Assign the note to another session." unless row

      { "session" => row["session"], "agent" => "#{row["name"].presence || "MCP agent"} · #{row["handle"]}" }
    end

    def busy?(db, app, session)
      db.get_first_value("SELECT COUNT(*) FROM notes WHERE project = ? AND session = ? AND status = 'working' AND archived_at IS NULL", [ app, session ]).to_i.positive?
    end

    # Another connected session that is waiting in watch_notes and working on no note.
    def idle_listener?(db, app, except:)
      db.execute("SELECT session FROM agents WHERE project = ? AND session != ? AND listening = 1 AND seen_at > ?", [ app, except.to_s, Time.now.to_f - WINDOW ])
        .any? { Presence.alive?(it["session"]) && !busy?(db, app, it["session"]) }
    end

    # Two words from the session id, such as amber-fox, so the person can tell sessions apart on the
    # page and match one to a terminal. offset picks the next pair, for a session whose first pair is
    # taken (free_handle).
    def handle(session, offset = 0)
      hex = session.to_s
      return nil unless hex.match?(SESSION)

      first, second = HANDLE_WORDS
      n = hex[0, 2].to_i(16) * second.size + hex[2, 2].to_i(16) + offset
      "#{first[(n / second.size) % first.size]}-#{second[n % second.size]}"
    end

    # The first handle for session that no other connected session of this app has.
    def free_handle(session)
      taken = Project.read do |db, app|
        db.execute("SELECT session, handle FROM agents WHERE project = ? AND session != ? AND seen_at > ?", [ app, session.to_s, Time.now.to_f - WINDOW ])
          .select { Presence.alive?(it["session"]) }.map { it["handle"] }
      end
      (0...(HANDLE_WORDS.first.size * HANDLE_WORDS.last.size)).lazy.map { handle(session, it) }.find { !taken.include?(it) } || handle(session)
    end

    # A directory as the page shows it: relative to the app root when inside it, else its name.
    def folder(cwd)
      return nil if cwd.blank?

      path = Pathname(cwd)
      root = Tensaku.root.expand_path
      return "#{root.basename}/" if path == root
      return "#{path.relative_path_from(root)}/" if path.to_s.start_with?("#{root}/")

      "#{path.basename}/"
    end
  end
end
