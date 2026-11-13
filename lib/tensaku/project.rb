require "json"
require "set"
require "time"

module Tensaku
  # The app at Tensaku.root, as a row of the database (see Store). One database holds every app and
  # checkout on the machine; each is a project named by its real path and sees only its own notes,
  # agents and selection. Notes and Agents read and write through here.
  #
  # Each write logs a row in `changes`, so a reader asks "anything after the last change I saw?"
  # (version) instead of reading every note, and Doorbell wakes the readers that wait.
  module Project
    OPENED = Set.new

    module_function

    # The app's real path, its key in every table.
    def current
      root = Tensaku.root.expand_path
      (root.exist? ? root.realpath : root).to_s
    end

    # Adds the app to the database the first time this process uses it.
    def opened
      key = [ Store.path.to_s, current ]
      return key.last if Store::LOCK.synchronize { OPENED.include?(key) }

      Store.write do |db|
        db.execute("INSERT OR IGNORE INTO projects (root, remote, created_at) VALUES (?, ?, ?)", [ key.last, Repo.remote(Tensaku.root), timestamp ])
      end
      Store::LOCK.synchronize { OPENED << key }
      key.last
    end

    # A write to this app's rows: the block runs in a transaction, and readers waiting on the doorbell
    # are woken after it commits.
    def write
      app = opened
      Store.write { |db| yield db, app }
    end

    def read
      app = opened
      Store.read { |db| yield db, app }
    end

    # Logs a change, so readers that wait for one see it (version) and get woken (Doorbell).
    def changed!(db, app, kind, note_id = nil)
      db.execute("INSERT INTO changes (project, kind, note_id, at) VALUES (?, ?, ?, ?)", [ app, kind, note_id, Time.now.to_f ])
      Store.ring(Tensaku.root)
    end

    # Changes whenever a note, the selection or an agent changes, or an agent connects or goes away: the
    # last change's number plus who is connected, in one query instead of a read of every note. Read it
    # in a write transaction (Project.write) when a note written just before must show in it.
    def version(now: Time.now)
      read do |db, app|
        seq = db.get_first_value("SELECT MAX(seq) FROM changes WHERE project = ?", [ app ]).to_i
        [ seq, Agents.connected_sessions(db, app, now:).sort ].hash
      end
    end

    # The page's base URL as the browser last sent it (for example https://shop.localhost), so an agent
    # gets full links. Written by the dev server, read by `tensaku mcp`.
    def base_url
      read { |db, app| db.get_first_value("SELECT base_url FROM projects WHERE root = ?", [ app ]) }
    end

    def base_url=(url)
      return if url.blank? || base_url == url

      write { |db, app| db.execute("UPDATE projects SET base_url = ? WHERE root = ?", [ url, app ]) }
    end

    # What the overlay last selected, in any tab, for the MCP `current_selection` tool.
    def selection
      read do |db, app|
        row = db.get_first_row("SELECT data FROM selections WHERE project = ? ORDER BY at DESC LIMIT 1", [ app ])
        row && JSON.parse(row["data"])
      end
    end

    # value is what the overlay sent: url, targets, text. Each tab keeps its own.
    def select!(value, tab:)
      value = value.to_h.stringify_keys.merge("at" => timestamp)
      write do |db, app|
        db.execute("INSERT INTO selections (project, tab, url, data, at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (project, tab) DO UPDATE SET url = excluded.url, data = excluded.data, at = excluded.at",
          [ app, tab.to_s.presence || "page", value["url"], JSON.generate(value), value["at"] ])
        changed!(db, app, "selection")
      end
    end

    # Timestamps carry microseconds, so watch_notes can tell apart notes saved within one second.
    def timestamp(time = Time.now)
      time.utc.iso8601(6)
    end
  end
end
