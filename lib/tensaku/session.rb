require "json"
require "securerandom"

module Tensaku
  # One agent session over one or more apps, behind `tensaku mcp` (Mcp) and `tensaku notes` (CLI). It
  # answers the tools in Session::Tools, and runs without Rails on Tensaku's database for each app.
  #
  # While it runs it checks in to each app's agents table (Agents.seen!), so the page shows the agent as
  # connected, and as listening while a watch_notes call waits.
  #
  # Claude Code channels: given a push (Mcp passes one that writes a channel notification), the session
  # sends Mcp's hello with channel_code and treats the channel as working once the agent calls
  # channel_ready with that code. From then on it claims each note saved on the page, as watch_notes
  # would, and pushes it into the session.
  class Session
    autoload :Tools, "tensaku/session/tools"

    MAX_WATCH = 300
    HEARTBEAT = 5
    # A watch sleeps on the doorbell, and looks anyway this often, for a note whose owner went away.
    RECHECK = 10
    LOG = "tmp/tensaku/mcp.log"
    LOG_LIMIT = 1_000_000

    include Tools

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
      result[:content].first[:text] += " #{left(except: Array(handed))}" if Tools::CLOSING.include?(name.to_s) && !result[:isError]
      log(name, started, result, handed)
      result
    end

    private

    def run(name, arguments)
      return result("Unknown tool #{name}", error: true) unless Tools::NAMES.include?(name.to_s)

      send(name.to_s, arguments)
    rescue Error, ArgumentError => error
      result(error.message, error: true)
    rescue StandardError => error
      warn "[Tensaku] #{error.class}: #{error.message}\n#{Array(error.backtrace).first(10).join("\n")}"
      result("Tensaku hit an error: #{error.class}: #{error.message}", error: true)
    end

    # How many open notes this session may take, besides those handed over in this answer, so an agent
    # that closed a note knows whether to list again without a call to find out.
    def left(except: [])
      open = per_app { Notes.list(status: "open", session: id).map { it["id"] } }.flat_map(&:last) - except
      other = "other " if except.any?
      return "#{open.size} #{other}open #{open.size == 1 ? "note is" : "notes are"} left: list_notes has #{open.size == 1 ? "it" : "them"}." if open.any?

      "No #{other}open notes left.#{" Call watch_notes to keep listening." if @watched && !@channel && except.empty?}"
    end

    def news(result)
      if @watched
        found = claim_since(@checked_at)
        return [] if found.empty?

        result[:content] << { type: "text", text: "Notes the person saved while you worked. They are yours and already started; work through them next:\n\n#{notes_markdown(found)}" }
        ids(found)
      else
        now = Time.now.utc
        sent = per_app { Notes.sent_between(@checked_at, now, session: id) }.flat_map(&:last).map { it["id"] }
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
            @push.call("Notes the person saved on the page. They are yours and already started: work through them one at a time, resolving each as soon as its change is made.\n\n#{notes_markdown(found)}", kind: "notes", notes: ids(found).join(" "))
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

    # Runs the block in each app: [[app, value], ...].
    def per_app(&block)
      apps.map { |app| [ app, Tensaku.with_root(app, &block) ] }
    end

    def change(note_id, **changes)
      in_app_of(note_id) { Notes.update(note_id, agent: label, session: id, **changes) }
    end

    def in_app_of(note_id, &block)
      app, = Notes.locate(apps, note_id)
      Tensaku.with_root(app, &block)
    end

    # Notes from several apps ([[app, notes], ...]) as one Markdown text, or "" when there are none.
    def notes_markdown(found)
      found.filter_map do |app, notes|
        Tensaku.with_root(app) { Notes::Markdown.list(notes, app: app_label(app), latest: true, session: id, absolute: true) } if notes.any?
      end.join("\n\n")
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
