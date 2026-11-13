require "json"
require "time"
require "set"
require "securerandom"

module Tensaku
  # Notes, the agents working on them and the page's selection, in the database in Tensaku.home (see
  # Store). The dev server and `tensaku mcp` (a separate process without Rails) both read and write
  # them. Each app is a project, named by its real path, so one database holds every app and checkout
  # on the machine, and each sees only its own notes.
  #
  # Timestamps carry microseconds, so watch_notes can tell apart notes saved within one second.
  #
  # A note is open until an agent (or you) resolves it, an agent declines it, or an agent asks something
  # back and sets it to `question`. An agent sets `working` when it picks a note up. What the agent and
  # you say to each other is the note's thread. Closed notes move to the archive after
  # Tensaku.config.archive_after, or when you archive them from the page.
  #
  # `sent_at` says when the note was last sent to an agent: when you saved it, or last edited, answered
  # or reopened it.
  module Notes
    STATUSES = %w[open working question resolved declined].freeze
    # The statuses that still need something from an agent or from you.
    ACTIVE = %w[open working question].freeze
    CLOSED = %w[resolved declined].freeze
    # An agent counts as connected for this long after its process last checked in.
    AGENT_WINDOW = 20
    # Rows of agents that stopped without cleaning up, and the change log, are deleted after this long.
    STALE_AFTER = 86_400
    SCREENSHOT_LIMIT = 4_000_000
    ID = /\A[a-z0-9]{4,12}\z/
    SESSION = /\A[a-f0-9]{32}\z/
    TARGET_KINDS = %w[element text translation markdown].freeze
    AUTHORS = %w[you agent].freeze

    class NotFound < Error; end

    # The note belongs to another agent session that is still running.
    class Taken < Error; end

    OPENED = Set.new

    module_function

    # The app the notes belong to, by its real path.
    def project
      root = Tensaku.root.expand_path
      (root.exist? ? root.realpath : root).to_s
    end

    # Adds the app to the database the first time this process uses it.
    def opened
      key = [ Store.path.to_s, project ]
      return key.last if Store::LOCK.synchronize { OPENED.include?(key) }

      Store.write do |db|
        db.execute("INSERT OR IGNORE INTO projects (root, remote, created_at) VALUES (?, ?, ?)", [ key.last, Repo.remote(Tensaku.root), timestamp ])
      end
      Store::LOCK.synchronize { OPENED << key }
      key.last
    end

    # A write to this app's notes: the block runs in a transaction, and readers waiting on the doorbell
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

    def all(archived: false)
      read { |db, app| load_notes(db, "project = ? AND archived_at IS #{archived ? "NOT " : ""}NULL ORDER BY created_at", [ app ]) }
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

      read { |db, app| load_notes(db, "project = ? AND id = ?", [ app, id ]).first } or raise NotFound, "No note #{id.inspect}"
    end

    # A string as SQLite should compare it. A binary string (a note id from a request path) would be
    # bound as a blob and never equal the text in the table.
    def text(value)
      value.to_s.dup.force_encoding(Encoding::UTF_8)
    end

    # attributes come from the overlay: url, comment, targets, for area notes rect and viewport, and
    # `to`, the handle of the agent session the note is for (see addressed).
    def create(attributes)
      attributes = attributes.to_h.stringify_keys
      comment = attributes["comment"].to_s.strip
      raise Error, "A note needs a comment" if comment.empty?

      note = {
        "url" => attributes["url"].to_s,
        "comment" => comment,
        "targets" => Array(attributes["targets"]).map { target(it) },
        "rect" => rect(attributes["rect"]),
        "viewport" => attributes["viewport"]&.to_s,
        "status" => "open",
        "commit" => Repo.head(Tensaku.root)
      }
      # The id and the time are taken in the write transaction, so sent_between never scans past a note
      # that is about to be written with an earlier sent_at.
      write do |db, app|
        now = timestamp
        note = note.merge("id" => new_id(db), "sent_at" => now, "created_at" => now, "updated_at" => now).compact_blank.merge("thread" => [])
        save(db, app, note.merge(addressed(db, app, attributes["to"])))
      end
    end

    # message adds to the note's thread, from "you" or "agent". send sends the note to an agent again.
    # session is the agent session making the change; another running session's note is refused.
    #
    # to (from the page) gives an open note to the agent session with that handle, or to whichever
    # agent takes it first when blank, and sends it again.
    def update(id, status: nil, comment: nil, message: nil, from: "agent", agent: nil, session: nil, send: false, to: nil)
      write do |db, app|
        note = find(id)
        check_owner!(note, session) if session
        unless to.nil?
          raise Error, "Only an open note can be sent to another agent" unless (status || note["status"]).to_s == "open"

          note = note.merge("session" => nil, "agent" => nil, "delivered_at" => nil, "delivered_to" => nil).merge(addressed(db, app, to))
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
      write do |db, app|
        find(id)
        db.execute("INSERT OR REPLACE INTO screenshots (note_id, png, width, height) VALUES (?, ?, ?, ?)", [ text(id), SQLite3::Blob.new(png), width, height ])
        changed!(db, app, "note", text(id))
      end
      { "width" => width, "height" => height }
    end

    # The note's screenshot: png (binary), width and height, or nil.
    def screenshot(id)
      find(id)
      read do |db|
        row = db.get_first_row("SELECT png, width, height FROM screenshots WHERE note_id = ?", [ text(id) ])
        row && { "png" => row["png"].to_s.b, "width" => row["width"], "height" => row["height"] }
      end
    end

    # The owner fields of a note for the connected agent session whose handle is handle: that session
    # alone gets it, as if it had claimed it. Blank means any agent.
    def addressed(db, app, handle)
      return {} if handle.blank?

      row = db.execute("SELECT session, name, handle, pid FROM agents WHERE project = ? AND handle = ? AND seen_at > ?", [ app, handle.to_s, Time.now.to_f - AGENT_WINDOW ])
        .find { alive?(it["pid"]) }
      raise Error, "#{handle} isn't connected any more. Send the note to another agent." unless row

      { "session" => row["session"], "agent" => "#{row["name"].presence || "MCP agent"} · #{row["handle"]}" }
    end

    # Marks the note as being worked on by session, which then owns it. Refused, in any status, when
    # another session that is still running owns it; a note whose session quit can be taken.
    def start(id, agent: nil, session: nil)
      write do |db, app|
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
      owner.nil? || session.nil? || owner == session || !agent_connected?(owner)
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

        entry = { "from" => from.to_s, "text" => message.to_s.strip, "agent" => agent.presence, "at" => timestamp }.compact
        note["thread"] = Array(note["thread"]) << entry
      end
      note["agent"] = agent if status.to_s == "working" && agent.present?
      note["updated_at"] = timestamp
      note["sent_at"] = note["updated_at"] if send
      # A note you reopen comes back from the archive.
      note.delete("archived_at") if ACTIVE.include?(note["status"])
      save(db, app, note)
    end

    def delete(id)
      write do |db, app|
        find(id)
        db.execute("DELETE FROM notes WHERE project = ? AND id = ?", [ app, text(id) ])
        changed!(db, app, "note", text(id))
      end
    end

    # Moves closed notes to the archive. They stay listable (status "archived") and come back when
    # reopened.
    def archive!(ids)
      write do |db, app|
        now = timestamp
        ids = Array(ids).map { text(it) }.grep(ID)
        archived = ids.select do |id|
          db.execute("UPDATE notes SET archived_at = ? WHERE project = ? AND id = ? AND archived_at IS NULL AND status IN ('resolved', 'declined')", [ now, app, id ])
          db.changes.positive?
        end
        archived.each { changed!(db, app, "note", it) }
        archived
      end
    end

    # Archives closed notes older than archive_after, and deletes old change rows and agent rows.
    def prune!(now: Time.now)
      cutoff = (now - Tensaku.config.archive_after).utc.iso8601(6)
      old = read { |db, app| db.execute("SELECT id FROM notes WHERE project = ? AND archived_at IS NULL AND status IN ('resolved', 'declined') AND updated_at < ?", [ app, cutoff ]).map { it["id"] } }
      archive!(old) if old.any?
      Store.write do |db|
        db.execute("DELETE FROM changes WHERE at < ?", [ now.to_f - STALE_AFTER ])
        db.execute("DELETE FROM agents WHERE seen_at < ?", [ now.to_f - STALE_AFTER ])
      end
    end

    # The open notes sent after since and up to upto that session may take. The scan runs in a write
    # transaction, and notes get their sent_at in one, so a caller that took upto before calling and
    # passes it as the next since sees every note exactly once.
    def sent_between(since, upto, session: nil)
      write do
        all.select { it["status"] == "open" && it["sent_at"] && it["sent_at"] > iso(since) && it["sent_at"] <= iso(upto) && available_to?(it, session) }
      end
    end

    # sent_between, and the notes found become session's in the same transaction: delivered_at and
    # delivered_to say they arrived. Two sessions scanning at once can't both get a note. updated_at and
    # sent_at stay: delivery isn't a change the person or the agent made.
    #
    # A session busy with a note leaves new ones to a listening session that has nothing to do, except
    # the notes the person sent to it.
    def claim_sent(since, upto, session:, agent:)
      write do |db, app|
        own_only = busy?(db, app, session) && idle_listener?(db, app, except: session)

        now = timestamp
        sent_between(since, upto, session:).filter_map do |note|
          next if own_only && note["session"] != session
          # Already handed to this session since it was last sent: by a watch running in the
          # background, or with the answer of another call.
          next if note["session"] == session && note["delivered_at"].to_s >= note["sent_at"].to_s

          save(db, app, note.merge("session" => session, "agent" => note["session"] == session ? note["agent"] || agent : agent, "delivered_at" => now, "delivered_to" => agent))
        end
      end
    end

    def busy?(db, app, session)
      db.get_first_value("SELECT COUNT(*) FROM notes WHERE project = ? AND session = ? AND status = 'working' AND archived_at IS NULL", [ app, session ]).to_i.positive?
    end

    # Another connected session that is waiting in watch_notes and working on no note.
    def idle_listener?(db, app, except:)
      db.execute("SELECT session, pid FROM agents WHERE project = ? AND session != ? AND listening = 1 AND seen_at > ?", [ app, except.to_s, Time.now.to_f - AGENT_WINDOW ])
        .any? { alive?(it["pid"]) && !busy?(db, app, it["session"]) }
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
      value = value.to_h.stringify_keys.merge("at" => Time.now.utc.iso8601(6))
      write do |db, app|
        db.execute("INSERT INTO selections (project, tab, url, data, at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (project, tab) DO UPDATE SET url = excluded.url, data = excluded.data, at = excluded.at",
          [ app, tab.to_s.presence || "page", value["url"], JSON.generate(value), value["at"] ])
        changed!(db, app, "selection")
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

    # Each `tensaku mcp` process checks in every few seconds while it runs: the client's name, its
    # handle, the directory it runs in, when it started, whether a watch_notes call is waiting, and its
    # last tool call ({ "tool", "note", "at" }). The page reads them to say who is connected and what each is doing. A check-in with nothing new isn't a change.
    def agent_seen!(session, name:, handle: nil, listening: false, cwd: nil, started_at: nil, last: nil, pid: Process.pid)
      row = [ name.to_s, (handle || self.handle(session)).to_s, listening ? 1 : 0, cwd, pid, started_at, last && JSON.generate(last) ]
      write do |db, app|
        before = db.get_first_row("SELECT name, handle, listening, cwd, pid, started_at, last, seen_at FROM agents WHERE session = ? AND project = ?", [ session, app ])
        db.execute(<<~SQL, [ session, app, *row, Time.now.to_f ])
          INSERT INTO agents (session, project, name, handle, listening, cwd, pid, started_at, last, seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT (session, project) DO UPDATE SET name = excluded.name, handle = excluded.handle, listening = excluded.listening,
            cwd = excluded.cwd, pid = excluded.pid, started_at = excluded.started_at, last = excluded.last, seen_at = excluded.seen_at
        SQL
        reconnected = before && before["seen_at"] < Time.now.to_f - AGENT_WINDOW
        changed!(db, app, "agent") if before.nil? || reconnected || before.values_at("name", "handle", "listening", "cwd", "pid", "started_at", "last") != row
      end
    end

    # Changes whenever a note, the selection or an agent changes, or an agent connects or goes away.
    # The last change's number plus who is connected: one query, not a read of every note. Read it in a
    # write transaction (Notes.write) when a note written just before must show in it.
    def version(now: Time.now)
      read do |db, app|
        seq = db.get_first_value("SELECT MAX(seq) FROM changes WHERE project = ?", [ app ]).to_i
        connected = db.execute("SELECT session, pid FROM agents WHERE project = ? AND seen_at > ?", [ app, now.to_f - AGENT_WINDOW ])
          .select { alive?(it["pid"]) }.map { it["session"] }.sort
        [ seq, connected ].hash
      end
    end

    HANDLE_WORDS = [
      %w[amber brisk calm dusky eager fern gilded hazy ivory jolly keen lucid misty noble olive plum quiet rosy sandy tidy umber vivid wary young zesty bold coral dewy frosty grassy lemon mossy],
      %w[fox heron otter lynx wren badger crane finch gecko hare ibis koala lark mole newt owl panda quail raven seal tern vole wolf yak bison camel dingo egret ferret moth stoat toad]
    ].freeze

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
      taken = read do |db, app|
        db.execute("SELECT session, handle, pid FROM agents WHERE project = ? AND session != ? AND seen_at > ?", [ app, session.to_s, Time.now.to_f - AGENT_WINDOW ])
          .select { alive?(it["pid"]) }.map { it["handle"] }
      end
      (0...(HANDLE_WORDS.first.size * HANDLE_WORDS.last.size)).lazy.map { handle(session, it) }.find { !taken.include?(it) } || handle(session)
    end

    def agent_gone!(session)
      write do |db, app|
        db.execute("DELETE FROM agents WHERE session = ? AND project = ?", [ session.to_s, app ])
        changed!(db, app, "agent") if db.changes.positive?
      end
    end

    # Whether session still owns its notes: its process is running. A late check-in (a database busy for
    # a while, a suspended laptop) doesn't free a note an agent is working on; a crashed or closed agent
    # frees it at once.
    def agent_connected?(session)
      return false unless session.to_s.match?(SESSION)

      read do |db, app|
        row = db.get_first_row("SELECT pid, seen_at FROM agents WHERE session = ? AND project = ?", [ session.to_s, app ])
        row && alive?(row["pid"])
      end
    end

    # Whether a process on this machine is running.
    def alive?(pid)
      Process.kill(0, pid.to_i)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # The agents connected to this app, oldest first: name, handle, the directory it runs in (relative
    # to the app when inside it), when it started, whether it is listening, its last tool call, and the
    # notes it is working on.
    def agents(now: Time.now)
      working = all.select { it["status"] == "working" }.group_by { it["session"] }
      rows = read { |db, app| db.execute("SELECT * FROM agents WHERE project = ? AND seen_at > ?", [ app, now.to_f - AGENT_WINDOW ]) }
      rows.select { alive?(it["pid"]) }.map do |row|
        last = row["last"] && JSON.parse(row["last"])
        {
          "name" => row["name"].presence || "MCP agent",
          "handle" => row["handle"],
          "folder" => folder(row["cwd"]),
          "started_at" => row["started_at"],
          "listening" => row["listening"] == 1,
          "last" => last.is_a?(Hash) ? last.slice("tool", "note", "at") : nil,
          "working" => Array(working[row["session"]]).map { { "id" => it["id"], "url" => it["url"], "comment" => it["comment"].to_s.squish.truncate(80) } }
        }.compact
      end.sort_by { [ it["started_at"].to_s, it["name"] ] }
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

    # One line per note, for a chat where the detailed form is too long.
    def to_short_markdown(notes)
      notes = Array(notes)
      return "No notes." if notes.empty?

      notes.map do |note|
        where = Array(note["targets"]).filter_map { [ it["file"], it["range"]&.split("-")&.first ].compact.join(":").presence }.uniq.first(3)
        "- `#{note["id"]}` (#{note["status"]}) #{note["comment"].squish.truncate(160)}#{" at #{where.map { "`#{it}`" }.join(", ")}" if where.any?}"
      end.join("\n")
    end

    # app names the app in each heading, for an agent that sees notes from several apps. With
    # latest: true each thread is cut down to what is new (see latest_thread).
    # session, the agent session the list is for, adds whether each note is its own.
    def to_markdown(notes, app: nil, latest: false, session: nil)
      notes = Array(notes)
      return "No notes." if notes.empty?

      base = base_url
      notes.map { note_markdown(it, base:, app:, latest:, session:) }.join("\n\n")
    end

    # A long back-and-forth repeated on every watch_notes call costs the agent its context, so a list
    # keeps the agent's latest message and everything after it, and says how many came before.
    def latest_thread(thread)
      last_agent = thread.rindex { it["from"] == "agent" }
      kept = last_agent ? thread[last_agent..] : thread.last(2)
      [ thread.size - kept.size, kept ]
    end

    def note_markdown(note, base: base_url, app: nil, latest: false, session: nil)
      page = base && note["url"].to_s.start_with?("/") ? "#{base.chomp("/")}#{note["url"]}" : note["url"]
      lines = [ "## Tensaku note #{note["id"]} (#{note["status"]}) on #{page}#{" in #{app}" if app}", "" ]
      if session && ACTIVE.include?(note["status"])
        lines << (note["session"] == session ? "*Yours.*" : "*Nobody's yet: call start_note before you work on it, so no other session takes it.*") << ""
      end
      lines << note["comment"]
      targets = Array(note["targets"])
      if targets.any?
        lines << ""
        targets.each { lines << "- #{target_markdown(it)}" }
      end
      if (rect = note["rect"])
        lines << "" << "Area: #{rect["width"]}x#{rect["height"]} at (#{rect["x"]}, #{rect["y"]}) in a #{note["viewport"] || "unknown"} viewport"
      end
      if (shot = note["screenshot"])
        lines << "" << "Screenshot: #{shot["width"]}x#{shot["height"]} PNG of what the note points at, as the page looked (get_screenshot #{note["id"]}, or `tensaku notes screenshot #{note["id"]}`)"
      end
      thread = Array(note["thread"])
      if thread.any?
        lines << ""
        skipped, thread = latest ? latest_thread(thread) : [ 0, thread ]
        lines << "> *(#{skipped} earlier #{skipped == 1 ? "message" : "messages"}; get_note #{note["id"]} has the whole thread)*" if skipped.positive?
        thread.each { lines << "> **#{it["from"] == "you" ? "You" : (it["agent"] || "Agent")}:** #{it["text"].to_s.gsub("\n", "\n> ")}" }
      end
      lines.join("\n")
    end

    def target_markdown(target)
      location = [ target["file"], target["range"] ].compact.join(":")
      parts = [ target["kind"] ]
      parts << "`#{target["tag"]}`" if target["tag"]
      parts << "`#{target["key"]}` (#{target["locale"]})" if target["key"]
      parts << "at `#{location}`" unless location.empty?
      parts << "\"#{target["text"].to_s.squish.truncate(120)}\"" if target["text"].present?
      parts << "classes `#{Array(target["classes"]).join(" ")}`" if target["classes"].present?
      context = target["context"].to_h.compact_blank
      parts << "(#{context.map { |key, value| "#{key}: #{Array(value).join(" < ")}" }.join(", ")})" if context.any?
      parts.join(" ")
    end

    # Fills in file positions from what the overlay saw: a Herb stamp, a translation key or a Markdown
    # range. A target whose source can't be read keeps what the page said about it.
    def target(raw)
      raise Error, "A note target must be a JSON object" unless raw.is_a?(Hash)

      raw = raw.stringify_keys
      kind = TARGET_KINDS.include?(raw["kind"]) ? raw["kind"] : "element"
      target = { "kind" => kind, "text" => raw["text"]&.to_s&.truncate(500), "tag" => raw["tag"]&.to_s }

      if raw["stamp"].present?
        target["stamp"] = raw["stamp"].to_s
        path, line, column = Source::Template.parse_stamp(raw["stamp"])
        target["file"] = path
        target["range"] = "#{line}:#{column}"
        begin
          target.merge!(Source::Template.new(path).element_range(line, column).stringify_keys)
        rescue Error
          nil
        end
      end

      if kind == "translation"
        target["key"] = raw["key"].to_s
        target["locale"] = raw["locale"].to_s
        if (entry = Source::Locale.find(target["locale"], target["key"]))
          target["file"] = entry[:file]
          target["range"] = entry[:line].to_s
        end
      end

      if kind == "markdown" && raw["md"].present?
        target["md"] = raw["md"].to_s
        target["file"], target["range"] = raw["md"].to_s.split(/:(?=\d+:\d+-)/, 2)
      end

      target["classes"] = Array(raw["classes"]).map(&:to_s).grep(/\A[^\s]{1,80}\z/).first(12)
      target["context"] = raw["context"].to_h.slice("partials", "controller", "frame").transform_values { Array(it).map(&:to_s).first(10) }.compact_blank
      target.compact_blank
    end

    def rect(raw)
      return nil unless raw.is_a?(Hash)

      raw.to_h.stringify_keys.slice("x", "y", "width", "height").transform_values { it.to_f.round }
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
      changed!(db, app, "note", note["id"])
      note
    end

    def load_notes(db, where, params)
      rows = db.execute("SELECT * FROM notes WHERE #{where}", params)
      return [] if rows.empty?

      ids = rows.map { it["id"] }
      marks = ("?, " * ids.size).chomp(", ")
      threads = db.execute("SELECT * FROM messages WHERE note_id IN (#{marks}) ORDER BY id", ids).group_by { it["note_id"] }
      shots = db.execute("SELECT note_id, width, height FROM screenshots WHERE note_id IN (#{marks})", ids).to_h { [ it["note_id"], it.slice("width", "height") ] }
      rows.map do |row|
        note = COLUMNS.to_h { [ it, row[it] ] }
        note["targets"] = JSON.parse(note["targets"] || "[]")
        note["rect"] = note["rect"] && JSON.parse(note["rect"])
        note["screenshot"] = shots[row["id"]]
        note.compact.merge("thread" => Array(threads[row["id"]]).map { { "from" => it["author"], "text" => it["text"], "agent" => it["agent"], "at" => it["at"] }.compact })
      end
    end

    def iso(time)
      time.utc.iso8601(6)
    end

    def timestamp
      Time.now.utc.iso8601(6)
    end
  end
end
