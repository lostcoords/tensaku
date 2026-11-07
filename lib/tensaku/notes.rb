require "json"
require "time"
require "fileutils"

module Tensaku
  # Notes are one JSON file each in tmp/tensaku/notes: local, ignored by git, cleared by tmp:clear.
  #
  # A note is open until an agent (or you) resolves it with a reply, or sets it to `question` with a
  # reply asking for more detail. An agent sets `working` when it picks a note up. Resolved notes are
  # deleted after Tensaku.config.prune_after.
  module Notes
    STATUSES = %w[open working question resolved].freeze
    # The statuses that still need something from an agent or from you.
    ACTIVE = %w[open working question].freeze
    # An agent counts as connected for this long after its last MCP call.
    AGENT_WINDOW = 20
    ID = /\A[a-z0-9]{4,12}\z/
    TARGET_KINDS = %w[element text translation markdown].freeze
    AUTHORS = %w[you agent].freeze
    SESSION = /\A[a-f0-9]{32}\z/

    class NotFound < Error; end

    module_function

    def dir
      Tensaku.root.join(Tensaku.config.notes_path)
    end

    def all
      return [] unless dir.directory?

      dir.glob("*.json").filter_map { read(it) }.sort_by { it["created_at"] }
    end

    def list(url: nil, status: nil)
      statuses = Array(status).map(&:to_s)
      all.select do |note|
        (url.nil? || note["url"] == url) && (statuses.empty? || statuses.include?(note["status"]))
      end
    end

    def find(id)
      raise NotFound, "No note #{id.inspect}" unless id.to_s.match?(ID)

      read(dir.join("#{id}.json")) or raise NotFound, "No note #{id.inspect}"
    end

    # attributes come from the overlay: url, comment, targets, and for area notes rect and viewport.
    def create(attributes)
      attributes = attributes.to_h.stringify_keys
      comment = attributes["comment"].to_s.strip
      raise Error, "A note needs a comment" if comment.empty?

      now = Time.now.utc.iso8601
      note = {
        "id" => new_id,
        "url" => attributes["url"].to_s,
        "comment" => comment,
        "targets" => Array(attributes["targets"]).map { target(it) },
        "rect" => rect(attributes["rect"]),
        "viewport" => attributes["viewport"]&.to_s,
        "status" => "open",
        "reply" => nil,
        "thread" => [],
        "created_at" => now,
        "updated_at" => now
      }.compact_blank.merge("reply" => nil, "thread" => [])
      write(note)
    end

    # message adds to the note's thread, from "you" or "agent". An agent's message is also the note's
    # reply, the line shown next to the pin. targets moves the note to other elements.
    def update(id, status: nil, reply: nil, comment: nil, message: nil, from: "agent", agent: nil, targets: nil)
      note = find(id)
      if status
        raise Error, "Status must be one of #{STATUSES.join(", ")}" unless STATUSES.include?(status.to_s)

        note["status"] = status.to_s
      end
      note["reply"] = reply.to_s.strip.presence unless reply.nil?
      note["comment"] = comment.to_s.strip unless comment.to_s.strip.empty?
      if message.present?
        raise Error, "A message is from one of #{AUTHORS.join(", ")}" unless AUTHORS.include?(from.to_s)

        entry = { "from" => from.to_s, "text" => message.to_s.strip, "agent" => agent.presence, "at" => Time.now.utc.iso8601 }.compact
        note["thread"] = Array(note["thread"]) << entry
        note["reply"] = entry["text"] if from.to_s == "agent"
      end
      note["agent"] = agent if agent.present? && status.to_s == "working"
      if targets
        note["targets"] = Array(targets).map { target(it) }
        note.delete("rect")
        note.delete("viewport")
      end
      note["updated_at"] = Time.now.utc.iso8601
      write(note)
    end

    def delete(id)
      find(id)
      dir.join("#{id}.json").delete
    end

    def prune!(now: Time.now)
      cutoff = now - Tensaku.config.prune_after
      all.each do |note|
        next unless note["status"] == "resolved" && Time.iso8601(note["updated_at"]) < cutoff

        dir.join("#{note["id"]}.json").delete
      end
      agents_dir.glob("*.json").each { it.delete if now - it.mtime > 86_400 } if agents_dir.directory?
    end

    # Blocks until a note is created or changed after `since`, or the timeout passes. Returns the open
    # notes that are new or changed. Polls the directory, which is plenty for one person and an agent.
    def watch(since:, timeout: 60, interval: 0.5)
      deadline = monotonic + timeout
      touched = monotonic
      loop do
        if monotonic - touched >= 5
          agent_seen!
          touched = monotonic
        end
        fresh = all.select { it["status"] == "open" && Time.iso8601(it["updated_at"]) > since }
        return fresh if fresh.any? || monotonic >= deadline

        sleep interval
      end
    end

    # Every MCP call touches a file next to the notes, so the overlay can show that an agent is
    # connected, whichever server process it talks to.
    # An MCP client that keeps the session id from initialize gets a file of its own with its name, so
    # the page can say which agent is connected. Other clients share one nameless file.
    def agent_seen!(session = nil)
      return touch(dir.join(".agent")) unless session.to_s.match?(SESSION)

      path = agents_dir.join("#{session}.json")
      path.file? ? FileUtils.touch(path) : write_agent(path, nil)
    end

    def register_agent(session, name)
      write_agent(agents_dir.join("#{session}.json"), name.to_s.truncate(80).presence)
    end

    def agent_name(session)
      return nil unless session.to_s.match?(SESSION)

      read(agents_dir.join("#{session}.json"))&.dig("name")
    end

    def agent
      files = [ dir.join(".agent"), *(agents_dir.directory? ? agents_dir.glob("*.json") : []) ].select(&:file?)
      return { "connected" => false, "seen_at" => nil, "names" => [] } if files.empty?

      recent = files.select { Time.now - it.mtime < AGENT_WINDOW }
      names = recent.filter_map { read(it)&.dig("name") if it.extname == ".json" }.uniq
      { "connected" => recent.any?, "seen_at" => files.map(&:mtime).max.utc.iso8601, "names" => names }
    end

    def agents_dir
      dir.join(".agents")
    end

    def touch(path)
      path.dirname.mkpath
      FileUtils.touch(path)
    end

    def write_agent(path, name)
      path.dirname.mkpath
      path.write(JSON.generate({ "name" => name }.compact) + "\n")
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

    def to_markdown(notes)
      notes = Array(notes)
      return "No notes." if notes.empty?

      notes.map { note_markdown(it) }.join("\n\n")
    end

    def note_markdown(note)
      lines = [ "## Tensaku note #{note["id"]} (#{note["status"]}) on #{note["url"]}", "", note["comment"] ]
      targets = Array(note["targets"])
      if targets.any?
        lines << ""
        targets.each { lines << "- #{target_markdown(it)}" }
      end
      if (rect = note["rect"])
        lines << "" << "Area: #{rect["width"]}x#{rect["height"]} at (#{rect["x"]}, #{rect["y"]}) in a #{note["viewport"] || "unknown"} viewport"
      end
      thread = Array(note["thread"])
      if thread.any?
        lines << ""
        thread.each { lines << "> **#{it["from"] == "you" ? "You" : (it["agent"] || "Agent")}:** #{it["text"].to_s.gsub("\n", "\n> ")}" }
      elsif note["reply"]
        lines << "" << "Reply: #{note["reply"]}"
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
      context = target["context"].to_h.compact_blank
      parts << "(#{context.map { |key, value| "#{key}: #{Array(value).join(" < ")}" }.join(", ")})" if context.any?
      parts.join(" ")
    end

    # Fills in file positions from what the overlay saw: a Herb stamp, a translation key or a Markdown
    # range. A target whose source can't be read keeps what the page said about it.
    def target(raw)
      raw = raw.to_h.stringify_keys
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

      target["context"] = raw["context"].to_h.slice("partials", "controller", "frame").transform_values { Array(it).map(&:to_s).first(10) }.compact_blank
      target.compact_blank
    end

    def rect(raw)
      return nil unless raw

      raw.to_h.stringify_keys.slice("x", "y", "width", "height").transform_values { it.to_f.round }
    end

    def new_id
      loop do
        id = SecureRandom.alphanumeric(4).downcase
        return id unless dir.join("#{id}.json").exist?
      end
    end

    def read(path)
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    def write(note)
      dir.mkpath
      path = dir.join("#{note["id"]}.json")
      temp = dir.join(".#{note["id"]}.json.tmp")
      temp.write(JSON.pretty_generate(note) + "\n")
      File.rename(temp, path)
      note
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
