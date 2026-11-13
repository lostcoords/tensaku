require "json"
require "time"
require "securerandom"

module Tensaku
  # The notes left on the pages of the app at Tensaku.root, in the database in Tensaku.home (see Store
  # and Project). The dev server and `tensaku mcp` (a separate process without Rails) both read and
  # write them. Markdown renders them for agents.
  #
  # A note is open until an agent (or you) resolves it, an agent declines it, or an agent asks something
  # back and sets it to `question`. An agent sets `working` when it picks a note up. What the agent and
  # you say to each other is the note's thread. Closed notes move to the archive after
  # Tensaku.config.archive_after, or when you archive them from the page.
  #
  # `sent_at` says when the note was last sent to an agent: when you saved it, or last edited, answered
  # or reopened it.
  module Notes
    autoload :Markdown, "tensaku/notes/markdown"
    autoload :Target, "tensaku/notes/target"

    STATUSES = %w[open working question resolved declined].freeze
    # The statuses that still need something from an agent or from you.
    ACTIVE = %w[open working question].freeze
    SCREENSHOT_LIMIT = 4_000_000
    ID = /\A[a-z0-9]{4,12}\z/
    AUTHORS = %w[you agent].freeze

    class NotFound < Error; end

    # The note belongs to another agent session that is still running.
    class Taken < Error; end

    module_function

    def all(archived: false)
      Project.read { |db, app| load_notes(db, "project = ? AND archived_at IS #{archived ? "NOT " : ""}NULL ORDER BY created_at", [ app ]) }
    end

    # session leaves out the notes another running agent session owns. status "archived" lists the
    # archive.
    def list(url: nil, status: nil, session: nil)
      statuses = Array(status).map(&:to_s)
      archived = statuses.delete("archived")
      notes = archived ? all(archived: true) : all
      notes.select do |note|
        (url.nil? || note["url"] == url) && (statuses.empty? || archived || statuses.include?(note["status"])) && available_to?(note, session)
      end
    end

    def find(id)
      id = text(id)
      raise NotFound, "No note #{id.inspect}" unless id.match?(ID)

      Project.read { |db, app| load_notes(db, "project = ? AND id = ?", [ app, id ]).first } or raise NotFound, "No note #{id.inspect}"
    end

    # A string as SQLite should compare it. A binary string (a note id from a request path) would be
    # bound as a blob and never equal the text in the table.
    def text(value)
      value.to_s.dup.force_encoding(Encoding::UTF_8)
    end

    # attributes come from the overlay: url, comment, targets, for area notes rect and viewport, and
    # `to`, the handle of the agent session the note is for (see Agents.owner).
    def create(attributes)
      attributes = attributes.to_h.stringify_keys
      comment = attributes["comment"].to_s.strip
      raise Error, "A note needs a comment" if comment.empty?

      note = {
        "url" => attributes["url"].to_s,
        "comment" => comment,
        "targets" => Array(attributes["targets"]).map { Target.from(it) },
        "rect" => Target.rect(attributes["rect"]),
        "viewport" => attributes["viewport"]&.to_s,
        "status" => "open",
        "commit" => Repo.head(Tensaku.root)
      }
      # The id and the time are taken in the write transaction, so sent_between never scans past a note
      # that is about to be written with an earlier sent_at.
      Project.write do |db, app|
        now = Project.timestamp
        note = note.merge("id" => new_id(db), "sent_at" => now, "created_at" => now, "updated_at" => now).compact_blank.merge("thread" => [])
        save(db, app, note.merge(Agents.owner(db, app, attributes["to"])))
      end
    end

    # message adds to the note's thread, from "you" or "agent". send sends the note to an agent again.
    # session is the agent session making the change; another running session's note is refused.
    #
    # to (from the page) gives an open note to the agent session with that handle, or to whichever
    # agent takes it first when blank, and sends it again.
    #
    # started: true refuses a note nobody started, for resolve_note: an agent has to call start_note
    # before changing anything, so two sessions can't work on one note unseen.
    def update(id, status: nil, comment: nil, message: nil, from: "agent", agent: nil, session: nil, send: false, to: nil, started: false)
      Project.write do |db, app|
        note = find(id)
        check_owner!(note, session) if session
        raise Error, "Note #{note["id"]} isn't started. Call start_note before you change anything for a note, then resolve it." if started && note["status"] != "working"
        # Assigning: to a session's handle, or blank for anyone. A note in progress can be taken back
        # from its session this way, for an agent stopped mid-work whose process still runs: it is open
        # again, and the old session's start_note and resolve_note are refused.
        unless to.nil?
          raise Error, "Only an open or in-progress note can be assigned" unless %w[open working].include?((status || note["status"]).to_s)

          note = note.merge("session" => nil, "agent" => nil, "delivered_at" => nil, "delivered_to" => nil).merge(Agents.owner(db, app, to))
          status = "open"
          send = true
        end
        apply(db, app, note, status:, comment:, message:, from:, agent:, send:)
      end
    end

    # A PNG of what the note points at, taken by the page when the note was written. The page sends it
    # as a data URL; screenshots larger than SCREENSHOT_LIMIT are refused.
    def attach_screenshot(id, data_url)
      match = data_url.to_s.match(%r{\Adata:image/png;base64,([A-Za-z0-9+/=]+)\z})
      raise Error, "A screenshot is a PNG data URL" unless match

      png = match[1].unpack1("m0")
      raise Error, "The screenshot is larger than #{SCREENSHOT_LIMIT / 1_000_000} MB" if png.bytesize > SCREENSHOT_LIMIT
      raise Error, "The screenshot isn't a PNG" unless png.start_with?("\x89PNG\r\n\x1A\n".b) && png.bytesize > 24

      width, height = png.byteslice(16, 8).unpack("NN")
      Project.write do |db, app|
        find(id)
        db.execute("INSERT OR REPLACE INTO screenshots (note_id, png, width, height) VALUES (?, ?, ?, ?)", [ text(id), SQLite3::Blob.new(png), width, height ])
        Project.changed!(db, app, "note", text(id))
      end
      { "width" => width, "height" => height }
    end

    # The note's screenshot: png (binary), width and height, or nil.
    def screenshot(id)
      find(id)
      Project.read do |db|
        row = db.get_first_row("SELECT png, width, height FROM screenshots WHERE note_id = ?", [ text(id) ])
        row && { "png" => row["png"].to_s.b, "width" => row["width"], "height" => row["height"] }
      end
    end

    # Marks the note as being worked on by session, which then owns it. Refused, in any status, when
    # another session that is still running owns it; a note whose session quit can be taken.
    def start(id, agent: nil, session: nil)
      Project.write do |db, app|
        note = find(id)
        check_owner!(note, session)
        note["session"] = session if session
        apply(db, app, note, status: "working", agent:)
      end
    end

    # A note belongs to the agent session that was handed it (claim_sent) or started it. Other sessions
    # leave it alone while that session runs, so two listeners never change the same thing, and a
    # request for changes goes back to the session that made them.
    def available_to?(note, session)
      owner = note["session"]
      owner.nil? || session.nil? || owner == session || !Agents.connected?(owner)
    end

    def check_owner!(note, session)
      return if available_to?(note, session)

      raise Taken, "Note #{note["id"]} belongs to #{note["agent"] || "another agent session"}, which is still running. Leave it, and take the next one."
    end

    def apply(db, app, note, status: nil, comment: nil, message: nil, from: "agent", agent: nil, send: false)
      if status
        raise Error, "Status must be one of #{STATUSES.join(", ")}" unless STATUSES.include?(status.to_s)

        note["status"] = status.to_s
      end
      note["comment"] = comment.to_s.strip unless comment.to_s.strip.empty?
      if message.present?
        raise Error, "A message is from one of #{AUTHORS.join(", ")}" unless AUTHORS.include?(from.to_s)

        entry = { "from" => from.to_s, "text" => message.to_s.strip, "agent" => agent.presence, "at" => Project.timestamp }.compact
        note["thread"] = Array(note["thread"]) << entry
      end
      note["agent"] = agent if status.to_s == "working" && agent.present?
      note["updated_at"] = Project.timestamp
      note["sent_at"] = note["updated_at"] if send
      # A note you reopen comes back from the archive.
      note.delete("archived_at") if ACTIVE.include?(note["status"])
      save(db, app, note)
    end

    def delete(id)
      Project.write do |db, app|
        find(id)
        db.execute("DELETE FROM notes WHERE project = ? AND id = ?", [ app, text(id) ])
        Project.changed!(db, app, "note", text(id))
      end
    end

    # Moves closed notes to the archive. They stay listable (status "archived") and come back when
    # reopened.
    def archive!(ids)
      Project.write do |db, app|
        now = Project.timestamp
        ids = Array(ids).map { text(it) }.grep(ID)
        archived = ids.select do |id|
          db.execute("UPDATE notes SET archived_at = ? WHERE project = ? AND id = ? AND archived_at IS NULL AND status IN ('resolved', 'declined')", [ now, app, id ])
          db.changes.positive?
        end
        archived.each { Project.changed!(db, app, "note", it) }
        archived
      end
    end

    # Archives closed notes older than archive_after, and lets the database forget old rows (Store.prune!).
    def prune!(now: Time.now)
      cutoff = (now - Tensaku.config.archive_after).utc.iso8601(6)
      old = Project.read { |db, app| db.execute("SELECT id FROM notes WHERE project = ? AND archived_at IS NULL AND status IN ('resolved', 'declined') AND updated_at < ?", [ app, cutoff ]).map { it["id"] } }
      archive!(old) if old.any?
      Store.prune!(now:)
    end

    # The open notes sent after since and up to upto that session may take. The scan runs in a write
    # transaction, and notes get their sent_at in one, so a caller that took upto before calling and
    # passes it as the next since sees every note exactly once.
    def sent_between(since, upto, session: nil)
      Project.write do
        all.select { it["status"] == "open" && it["sent_at"] && it["sent_at"] > Project.timestamp(since) && it["sent_at"] <= Project.timestamp(upto) && available_to?(it, session) }
      end
    end

    # sent_between, and the notes found become session's in the same transaction: delivered_at and
    # delivered_to say they arrived. Two sessions scanning at once can't both get a note. updated_at and
    # sent_at stay: delivery isn't a change the person or the agent made.
    #
    # A session busy with a note leaves new ones to a listening session that has nothing to do, except
    # the notes the person sent to it.
    def claim_sent(since, upto, session:, agent:)
      Project.write do |db, app|
        own_only = Agents.busy?(db, app, session) && Agents.idle_listener?(db, app, except: session)

        now = Project.timestamp
        sent_between(since, upto, session:).filter_map do |note|
          next if own_only && note["session"] != session
          # Already handed to this session since it was last sent: by a watch running in the
          # background, or with the answer of another call.
          next if note["session"] == session && note["delivered_at"].to_s >= note["sent_at"].to_s

          save(db, app, note.merge("session" => session, "agent" => note["session"] == session ? note["agent"] || agent : agent, "delivered_at" => now, "delivered_to" => agent))
        end
      end
    end

    # When an agent last said something on a note in this app (a resolve, a question, a reply), which
    # follows its changes to files. The page refreshes itself when this changes.
    def last_agent_message_at
      Project.read do |db, app|
        db.get_first_value(<<~SQL, [ app ])
          SELECT MAX(messages.at) FROM messages JOIN notes ON notes.id = messages.note_id
          WHERE notes.project = ? AND messages.author = 'agent'
        SQL
      end
    end

    def new_id(db)
      loop do
        id = SecureRandom.alphanumeric(4).downcase
        return id unless db.get_first_value("SELECT 1 FROM notes WHERE id = ?", [ id ])
      end
    end

    COLUMNS = %w[id url comment status targets rect viewport commit session agent sent_at delivered_at delivered_to archived_at created_at updated_at].freeze

    # Writes the whole note, thread included, and logs the change. Returns the note.
    def save(db, app, note)
      values = COLUMNS.map do |column|
        value = note[column]
        %w[targets rect].include?(column) ? (value.nil? ? (column == "targets" ? "[]" : nil) : JSON.generate(value)) : value
      end
      quoted = COLUMNS.map { %("#{it}") }
      db.execute(<<~SQL, [ app, *values ])
        INSERT INTO notes (project, #{quoted.join(", ")}) VALUES (?, #{("?, " * COLUMNS.size).chomp(", ")})
        ON CONFLICT (id) DO UPDATE SET #{quoted.drop(1).map { "#{it} = excluded.#{it}" }.join(", ")}
      SQL
      db.execute("DELETE FROM messages WHERE note_id = ?", [ note["id"] ])
      Array(note["thread"]).each do |entry|
        db.execute("INSERT INTO messages (note_id, author, agent, text, at) VALUES (?, ?, ?, ?, ?)", [ note["id"], entry["from"], entry["agent"], entry["text"], entry["at"] ])
      end
      Project.changed!(db, app, "note", note["id"])
      note
    end

    def load_notes(db, where, params)
      rows = db.execute("SELECT * FROM notes WHERE #{where}", params)
      return [] if rows.empty?

      ids = rows.map { it["id"] }
      marks = ("?, " * ids.size).chomp(", ")
      threads = db.execute("SELECT * FROM messages WHERE note_id IN (#{marks}) ORDER BY id", ids).group_by { it["note_id"] }
      shots = db.execute("SELECT note_id, width, height FROM screenshots WHERE note_id IN (#{marks})", ids).to_h { [ it["note_id"], it.slice("width", "height") ] }
      # A note in progress whose session's process ended: anyone can take it (available_to?).
      gone = rows.select { it["status"] == "working" && it["session"] }.map { it["session"] }.uniq.reject { Presence.alive?(it) }
      rows.map do |row|
        note = COLUMNS.to_h { [ it, row[it] ] }
        note["stopped"] = true if note["status"] == "working" && gone.include?(note["session"])
        note["targets"] = JSON.parse(note["targets"] || "[]")
        note["rect"] = note["rect"] && JSON.parse(note["rect"])
        note["screenshot"] = shots[row["id"]]
        note.compact.merge("thread" => Array(threads[row["id"]]).map { { "from" => it["author"], "text" => it["text"], "agent" => it["agent"], "at" => it["at"] }.compact })
      end
    end
  end
end
