require "json"
require "securerandom"

module Tensaku
  # One agent session over one or more apps: the tools an agent calls, by `tensaku mcp` (Mcp) or
  # `tensaku notes` (CLI). It runs without Rails and works on Tensaku's database for each app.
  #
  # While it runs it checks in to each app's agents table (Agents.seen!), so the page shows the agent as
  # connected, and as listening while a watch_notes call waits.
  #
  # Claude Code channels: given a push (Mcp passes one that writes a channel notification), the session
  # sends Mcp's hello with channel_code and treats the channel as working once the agent calls
  # channel_ready with that code. From then on it claims each note saved on the page, as watch_notes
  # would, and pushes it into the session.
  class Session
    MAX_WATCH = 300
    HEARTBEAT = 5
    # A watch sleeps on the doorbell, and looks anyway this often, for a note whose owner went away.
    RECHECK = 10
    LOG = "tmp/tensaku/mcp.log"
    LOG_LIMIT = 1_000_000

    attr_reader :apps, :id, :channel_code
    attr_accessor :name

    # apps are the root directories of the Rails apps to serve. push(content, **meta) sends a message
    # into the agent's chat, when the client supports one.
    def initialize(apps, name: "MCP agent", push: nil)
      @apps = apps.map { Pathname(it).expand_path }
      @id = SecureRandom.hex(16)
      @name = name
      @push = push
      @listening = 0
      @started_at = Time.now.utc.iso8601
      # When this agent last saw the sent notes (list_notes or watch_notes), for the line that tells a
      # busy agent about notes sent since.
      @checked_at = Time.now.utc
      @watched = false
      @last = nil
      @lock = Mutex.new
      @seen_lock = Mutex.new
      @claim_lock = Mutex.new
      @channel_code = SecureRandom.alphanumeric(8)
      @channel = false
    end

    def channel? = @channel

    # A thread that checks in every HEARTBEAT seconds, for a long-running session. Kill it before close.
    def heartbeat
      Thread.new { loop { seen!; sleep HEARTBEAT } }
    end

    # Takes this session off the page and stops pushing notes.
    def close
      @pusher&.kill
      @pusher = nil
      each_app { Agents.gone!(id) }
    end

    # One writer at a time, so the heartbeat can't write an old name or state over a newer one.
    def seen!
      @seen_lock.synchronize do
        each_app do
          Agents.seen!(id, name: @name, handle:, listening: @listening.positive?, channel: @channel, cwd: Dir.pwd, started_at: @started_at, last: @last)
        end
      end
    rescue SystemCallError, SQLite3::BusyException
      nil # a database busy for longer than its timeout is tried again at the next heartbeat
    end

    # Two words for this session, such as amber-fox, that no other connected session of its first app
    # has. Chosen once.
    def handle
      @handle ||= Tensaku.with_root(apps.first) { Agents.free_handle(id) }
    end

    # The client's name and this session's handle, as notes and the page show it: "Claude Code · amber-fox".
    def label
      "#{@name} · #{handle}"
    end

    # Records the call for the page, runs it, and tells the agent about notes sent since it last
    # looked: a session that has listened gets them in the answer, claimed like watch_notes would, so
    # it doesn't have to wait in watch_notes while it works. Any other session gets their ids.
    # Returns an MCP tool result: { content: [...], isError: }.
    def call(name, arguments = {})
      arguments = arguments.transform_keys(&:to_s)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @last = { "tool" => name.to_s, "note" => arguments["id"].presence, "at" => Time.now.utc.iso8601 }.compact
      seen!
      result = run(name, arguments)
      handed = result.delete(:handed) || (news(result) unless result[:isError] || %w[list_notes watch_notes].include?(name))
      log(name, started, result, handed)
      result
    end

    private

    # Replies are text only. A reply that repeated itself as structured data would cost an agent the
    # tokens twice, and a state change only needs an acknowledgement.
    def run(name, arguments)
      case name
      when "list_notes"
        status = arguments["status"].presence || "active"
        statuses = { "active" => Notes::ACTIVE, "all" => nil }.fetch(status, status)
        @checked_at = Time.now.utc
        url = arguments["url"].presence
        text = markdown { Notes.list(url:, status: statuses, session: id) }
        taken = apps.sum { |app| Tensaku.with_root(app) { Notes.list(url:, status: statuses).size - Notes.list(url:, status: statuses, session: id).size } }
        text += "\n\n#{taken} more #{taken == 1 ? "note belongs" : "notes belong"} to other running agent sessions and #{taken == 1 ? "isn't" : "aren't"} listed. Leave #{taken == 1 ? "it" : "them"} to those sessions." if taken.positive?
        result(text)
      when "get_note"
        app, note = find(arguments["id"])
        result(Tensaku.with_root(app) { Notes::Markdown.note(note, app: app_label(app)) })
      when "get_screenshot"
        shot = in_app_of(arguments["id"]) { Notes.screenshot(arguments["id"]) }
        return result("Note #{arguments["id"]} has no screenshot.", error: true) unless shot

        { content: [ { type: "image", data: [ shot["png"] ].pack("m0"), mimeType: "image/png" } ], isError: false }
      when "start_note"
        note = in_app_of(arguments["id"]) { Notes.start(arguments["id"], agent: label, session: id) }
        result("Started note #{note["id"]}. The page shows you as #{label}.")
      when "resolve_note"
        note = change(arguments["id"], status: "resolved", message: arguments["reply"], started: true)
        result("Resolved note #{note["id"]}.#{" Call watch_notes to keep listening." if @watched && !@channel}")
      when "decline_note"
        note = change(arguments["id"], status: "declined", message: arguments["reason"])
        result("Declined note #{note["id"]}.")
      when "ask_question"
        note = change(arguments["id"], status: "question", message: arguments["question"])
        result("Asked on note #{note["id"]}.")
      when "reply_to_note"
        note = change(arguments["id"], message: arguments["message"])
        result("Added a message to note #{note["id"]}.")
      when "watch_notes"
        since = arguments["since"].present? ? Time.iso8601(arguments["since"]) : Time.now.utc
        timeout = arguments["timeout_seconds"].nil? ? 60 : arguments["timeout_seconds"].to_i.clamp(1, MAX_WATCH)
        first = !@watched
        @watched = true
        found, checked_at = watch(since, timeout)
        @checked_at = [ @checked_at, checked_at ].max
        text = found.empty? ? "No new notes in #{timeout}s." : found_markdown(found)
        intro = "You are listening as #{label}. Tell the person this name: the page shows it, and the notes handed to you are yours.\n\n" if first
        result("#{intro}#{text}\n\nchecked_at: #{checked_at.iso8601(6)}").merge(handed: ids(found))
      when "channel_ready"
        return result("That isn't the code from Tensaku's channel event.", error: true) unless @push && arguments["code"].to_s == @channel_code

        start_channel
        waiting = apps.sum { |app| Tensaku.with_root(app) { Notes.list(status: Notes::ACTIVE, session: id).size } }
        result("Tensaku's channel works. Notes the person saves on the page arrive in this chat as #{label}, already yours. Tell the person in one line#{", and that #{waiting} earlier #{waiting == 1 ? "note is" : "notes are"} open (list_notes has them), without starting on them unless they ask" if waiting.positive?}.")
      when "current_selection"
        selection = apps.filter_map { |app| Tensaku.with_root(app) { Project.selection } }.max_by { it["at"].to_s }
        result(selection ? JSON.pretty_generate(selection) : "Nothing selected in the Tensaku overlay yet.")
      else
        result("Unknown tool #{name}", error: true)
      end
    rescue Error, ArgumentError => error
      result(error.message, error: true)
    rescue StandardError => error
      warn "[Tensaku] #{error.class}: #{error.message}\n#{Array(error.backtrace).first(10).join("\n")}"
      result("Tensaku hit an error: #{error.class}: #{error.message}", error: true)
    end

    def news(result)
      if @watched
        found = claim_since(@checked_at)
        return [] if found.empty?

        result[:content] << { type: "text", text: "Notes the person saved while you worked. They are yours now; work through them next:\n\n#{found_markdown(found)}" }
        ids(found)
      else
        now = Time.now.utc
        sent = apps.flat_map { |app| Tensaku.with_root(app) { Notes.sent_between(@checked_at, now, session: id) } }.map { it["id"] }
        result[:content] << { type: "text", text: "#{sent.size == 1 ? "1 note was" : "#{sent.size} notes were"} saved on the page since you last looked (#{sent.join(", ")}). Call watch_notes or list_notes next." } if sent.any?
        []
      end
    end

    # Waits until a note is sent in any app, or the timeout passes, and claims what it finds for this
    # session. Returns [[app, notes], ...] and the time to pass as the next since. The time is taken
    # before the scan; see Notes.sent_between.
    #
    # It waits on the doorbell and only scans an app whose notes changed since the last scan. The
    # version is read in a write transaction, after checked_at: a note sent before checked_at was
    # committed before the transaction could start, so it shows in the version.
    def watch(since, timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      versions = {}
      listening(+1)
      Doorbell.listen(apps) do |doorbell|
        loop do
          checked_at = Time.now.utc
          found = apps.filter_map do |app|
            Tensaku.with_root(app) do
              version = Project.write { Project.version }
              next if versions[app] == version

              versions[app] = version
              notes = Notes.claim_sent(since, checked_at, session: id, agent: label)
              [ app, notes ] if notes.any?
            end
          end
          left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return [ found, checked_at ] if found.any? || left <= 0

          doorbell.wait([ left, RECHECK ].min)
        end
      end
    ensure
      listening(-1)
    end

    # Claims the notes sent since time in every app, for an answer that isn't watch_notes.
    def claim_since(time)
      @claim_lock.synchronize do
        now = Time.now.utc
        found = apps.filter_map do |app|
          notes = Tensaku.with_root(app) { Notes.claim_sent(time, now, session: id, agent: label) }
          [ app, notes ] if notes.any?
        end
        @checked_at = [ @checked_at, now ].max
        found
      end
    end

    def start_channel
      return if @channel

      @channel = true
      @watched = true
      @checked_at = Time.now.utc
      listening(+1)
      @pusher = Thread.new { push_notes }
    end

    # Claims the notes saved on the page as they come and pushes them into the session, for as long as
    # the process runs. The doorbell wakes it at once; it also looks every RECHECK seconds, for a note
    # whose owner went away.
    def push_notes
      Doorbell.listen(apps) do |doorbell|
        loop do
          found = claim_since(@checked_at)
          if found.any?
            @push.call("Notes the person saved on the page. They are yours: work through them one at a time with start_note and resolve_note.\n\n#{found_markdown(found)}", kind: "notes", notes: ids(found).join(" "))
            log("channel", Process.clock_gettime(Process::CLOCK_MONOTONIC), { content: [] }, ids(found))
          end
          doorbell.wait(RECHECK)
        end
      end
    rescue StandardError => error
      warn "[Tensaku] channel: #{error.class}: #{error.message}"
      @pusher = nil
    end

    # One JSON line per tool call in each app's tmp/tensaku/mcp.log: which session, the tool, how long
    # it took, how big the answer was and the notes it handed over, to see what Tensaku costs an agent.
    def log(tool, started, result, handed)
      line = JSON.generate({
        at: Time.now.utc.iso8601(3), session: handle, agent: @name, tool:,
        ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
        bytes: result[:content].sum { it[:text].to_s.bytesize }, notes: Array(handed).presence, error: result[:isError] || nil
      }.compact) + "\n"
      each_app do
        path = Tensaku.root.join(LOG)
        path.dirname.mkpath
        File.rename(path, "#{path}.1") if path.file? && path.size > LOG_LIMIT
        File.write(path, line, mode: "a")
      end
    rescue SystemCallError
      nil
    end

    def listening(change)
      @lock.synchronize { @listening += change }
      seen!
    end

    def each_app(&block)
      apps.each { |app| Tensaku.with_root(app, &block) }
    end

    def change(note_id, **changes)
      in_app_of(note_id) { Notes.update(note_id, agent: label, session: id, **changes) }
    end

    def in_app_of(note_id, &block)
      app, = find(note_id)
      Tensaku.with_root(app, &block)
    end

    # The app that has the note, and the note.
    def find(note_id)
      apps.each do |app|
        return [ app, Tensaku.with_root(app) { Notes.find(note_id) } ]
      rescue Notes::NotFound
        next
      end
      raise Notes::NotFound, "No note #{note_id.inspect}"
    end

    # The notes the block lists in each app, as one Markdown text.
    def markdown(&block)
      parts = apps.filter_map do |app|
        Tensaku.with_root(app) do
          notes = block.call
          Notes::Markdown.list(notes, app: app_label(app), latest: true, session: id) if notes.any?
        end
      end
      parts.empty? ? "No notes." : parts.join("\n\n")
    end

    def found_markdown(found)
      found.map { |app, notes| Tensaku.with_root(app) { Notes::Markdown.list(notes, app: app_label(app), latest: true, session: id) } }.join("\n\n")
    end

    def ids(found)
      found.flat_map { |_, notes| notes.map { it["id"] } }
    end

    # The app's name in headings, when there is more than one app.
    def app_label(app)
      app.basename.to_s if apps.size > 1
    end

    def result(text, error: false)
      { content: [ { type: "text", text: } ], isError: error }
    end
  end
end
