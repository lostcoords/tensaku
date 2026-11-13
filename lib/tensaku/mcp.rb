require "json"
require "securerandom"

module Tensaku
  # The MCP server an agent starts with `tensaku mcp`: newline-delimited JSON-RPC over stdin and stdout.
  # It runs without Rails and works on Tensaku's database for each app it was given, so the dev server
  # doesn't have to be running and no port is configured.
  #
  # One process is one session. While it runs it checks in to each app's agents table, so the page
  # shows the agent as connected, and as listening while a watch_notes call waits.
  #
  # Claude Code channels: the server declares the experimental claude/channel capability, which lets it
  # push a message into a Claude Code session started with
  # `claude --dangerously-load-development-channels server:tensaku`; the message starts a turn as if the
  # person had typed it. A session without the flag drops these messages without an error, so the
  # server first sends a hello with a code and only treats the channel as working once Claude calls
  # channel_ready with that code. From then on it claims each note saved on the page, as watch_notes
  # would, and pushes it into the session.
  class Mcp
    PROTOCOL_VERSIONS = %w[2025-11-25 2025-06-18 2025-03-26 2024-11-05].freeze
    MAX_WATCH = 300
    HEARTBEAT = 5
    # A watch sleeps on the doorbell, and looks anyway this often, for a note whose owner went away.
    RECHECK = 10
    LOG = "tmp/tensaku/mcp.log"
    LOG_LIMIT = 1_000_000

    CHANNEL_INSTRUCTIONS = " This server may also be a Claude Code channel. Its events arrive as <channel source=\"tensaku\"> messages. The first one asks you to call channel_ready with a code: do that, then tell the person in one line that Tensaku notes now arrive in this chat. Each later event holds notes the person saved on the page, already yours: work through them like notes from watch_notes. There's no need to call watch_notes while the channel works."

    TOOLS = [
      {
        name: "list_notes",
        description: "List Tensaku notes left on pages of this Rails app. Each note has a comment and targets with the exact file and line range that rendered the element. Defaults to notes that need work (open, working and question), sent or not.",
        inputSchema: {
          type: "object",
          properties: {
            status: { type: "string", enum: %w[open working question resolved declined active all], description: "active (default) means open, working or question." },
            url: { type: "string", description: "Only notes left on this path, for example /about." }
          }
        }
      },
      {
        name: "get_note",
        description: "Get one Tensaku note by id.",
        inputSchema: { type: "object", properties: { id: { type: "string" } }, required: [ "id" ] }
      },
      {
        name: "get_screenshot",
        description: "Get the screenshot the page took of what a note points at, as a PNG, when the note says it has one. It shows the page as the person saw it when writing the note.",
        inputSchema: { type: "object", properties: { id: { type: "string" } }, required: [ "id" ] }
      },
      {
        name: "start_note",
        description: "Mark a note as being worked on before you make the change. The pin on the page shows that an agent has picked it up, and the note becomes this session's. Fails when the note belongs to another running agent session: then leave it. Call resolve_note as soon as the change is made.",
        inputSchema: { type: "object", properties: { id: { type: "string" } }, required: [ "id" ] }
      },
      {
        name: "resolve_note",
        description: "Mark a note resolved as soon as its change is made, before starting the next note. Only a note you started with start_note can be resolved. The person is watching the page, so don't save these up for the end. The reply is shown next to a green pin: say in one line what changed and where (for example: changed the heading in app/views/pages/_hero.html.erb:4).",
        inputSchema: { type: "object", properties: { id: { type: "string" }, reply: { type: "string" } }, required: %w[id reply] }
      },
      {
        name: "decline_note",
        description: "Close a note without changing anything, when the change shouldn't be made or can't be made here. The reason is shown on the page next to the note.",
        inputSchema: { type: "object", properties: { id: { type: "string" }, reason: { type: "string" } }, required: %w[id reason] }
      },
      {
        name: "ask_question",
        description: "Ask the person who wrote a note for clarification instead of guessing. The question shows on the page; the note's status becomes question until they answer on the note.",
        inputSchema: { type: "object", properties: { id: { type: "string" }, question: { type: "string" } }, required: %w[id question] }
      },
      {
        name: "reply_to_note",
        description: "Add a message to a note's thread without changing its status, for example to say what you found or what you will do. It shows on the page under the note.",
        inputSchema: { type: "object", properties: { id: { type: "string" }, message: { type: "string" } }, required: %w[id message] }
      },
      {
        name: "watch_notes",
        description: "Wait for notes the person saves on the page, so you can work through them as they arrive. Returns as soon as there are any, or empty after the timeout. While you wait, the page shows you as listening. Pass the checked_at value of the previous call as since so nothing is missed, and call it again after working through the notes to keep listening.",
        inputSchema: {
          type: "object",
          properties: {
            since: { type: "string", description: "ISO 8601 time. Defaults to now." },
            timeout_seconds: { type: "integer", minimum: 1, maximum: MAX_WATCH, description: "Defaults to 60." }
          }
        }
      },
      {
        name: "channel_ready",
        description: "Only when a Tensaku channel event asks for it: confirms that Tensaku's channel messages reach this session, so the person's notes are pushed here as they save them.",
        inputSchema: { type: "object", properties: { code: { type: "string", description: "The code from the channel event" } }, required: %w[code] }
      },
      {
        name: "current_selection",
        description: "What the person last selected in the Tensaku overlay (elements with file and line), for questions like 'what is this?'.",
        inputSchema: { type: "object", properties: {} }
      }
    ].freeze

    INSTRUCTIONS = "Tensaku notes are comments a person left on pages of this Rails app, each with the file and line that rendered the element. Work through open notes one at a time: start_note, make the change, then resolve_note with a one-line reply before the next note, so the page shows progress as it happens. Ask a question when a note is unclear, and decline_note when the change shouldn't be made. When the person asks you to watch or listen for notes, call watch_notes in a loop, and tell them the session name its first answer gives you (such as amber-fox), which the page shows next to your name. A note belongs to the session the person assigned it to, was handed it or started it: call start_note before you change anything for a note, and leave notes another session owns. A note with a screenshot says so; get_screenshot returns it. Once you have called watch_notes, notes sent while you work come with the answer of whichever Tensaku tool you call next, already yours: work through them, and call watch_notes again only when you have nothing else to do."

    attr_reader :apps, :session

    # apps are the root directories of the Rails apps to serve.
    def initialize(apps, output: $stdout)
      @apps = apps.map { Pathname(it).expand_path }
      @output = output
      @session = SecureRandom.hex(16)
      @name = "MCP agent"
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
      @calls = {}
      # See the class comment. channel_code is sent in the hello; @channel turns true when it comes back.
      @channel_code = SecureRandom.alphanumeric(8)
      @channel = false
      @claude = false
    end

    # Reads requests until stdin closes. Tool calls run in threads of their own, so a waiting
    # watch_notes doesn't hold up other requests and can be cancelled.
    def run(input = $stdin)
      heartbeat = Thread.new { loop { seen!; sleep HEARTBEAT } }
      input.each_line do |line|
        next if line.strip.empty?

        handle(line)
      end
    ensure
      heartbeat&.kill
      close_channel
      @lock.synchronize { @calls.values }.each(&:kill)
      each_app { Notes.agent_gone!(session) }
    end

    # One line of JSON-RPC: a request, a notification or a batch.
    def handle(line)
      message = JSON.parse(line)
      if message.is_a?(Hash) && message["method"] == "tools/call" && message.key?("id")
        id = message["id"]
        @lock.synchronize do
          @calls[id] = Thread.new do
            reply = respond(message)
            @lock.synchronize { @calls.delete(id) }
            write(reply)
          end
        end
      elsif message.is_a?(Array)
        replies = message.filter_map { respond(it) }
        write(replies) if replies.any?
      elsif (reply = respond(message))
        write(reply)
      end
    rescue JSON::ParserError
      write(error_payload(nil, -32700, "Parse error"))
    end

    private

    def respond(message)
      return error_payload(nil, -32600, "Invalid Request") unless message.is_a?(Hash)

      id = message["id"]
      if id.nil? # a notification
        cancel(message.dig("params", "requestId")) if message["method"] == "notifications/cancelled"
        greet if message["method"] == "notifications/initialized"
        return nil
      end

      result = case message["method"]
      when "initialize" then initialize_result(message["params"].to_h)
      when "ping" then {}
      when "tools/list" then { tools: TOOLS }
      when "tools/call" then tool_call(message.dig("params", "name"), message.dig("params", "arguments") || {})
      else return error_payload(id, -32601, "Method not found: #{message["method"]}")
      end
      { jsonrpc: "2.0", id:, result: }
    end

    def initialize_result(params)
      client = params["clientInfo"].to_h
      @name = (client["title"].presence || client["name"].presence || @name).to_s.truncate(80)
      # Channels are Claude Code's; other clients get neither the capability nor the hello.
      @claude = [ client["name"], client["title"] ].any? { it.to_s.match?(/claude/i) }
      seen!
      requested = params["protocolVersion"]
      capabilities = { tools: { listChanged: false } }
      capabilities[:experimental] = { "claude/channel" => {} } if @claude
      {
        protocolVersion: PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSIONS.first,
        capabilities:,
        serverInfo: { name: "tensaku", version: Tensaku::VERSION },
        instructions: INSTRUCTIONS + (@claude ? CHANNEL_INSTRUCTIONS : "")
      }
    end

    # Claude Code registers its channel listener a moment after initialization, and drops what comes
    # before it (seen in its debug log), so the hello waits, and is sent once more until answered.
    HELLO_AFTER = [ 1.5, 6 ].freeze

    def greet
      return unless @claude

      @greeter ||= Thread.new { HELLO_AFTER.each { sleep it; hello } }
    end

    # The first channel message. A session that loaded the channel gets it as a turn and calls
    # channel_ready; any other drops it.
    def hello
      return if @channel

      push("Tensaku is connected as #{agent_label}. To have the person's notes pushed into this chat as they save them, call the channel_ready tool with code #{@channel_code}, then tell the person in one line that their Tensaku notes now arrive here.", kind: "hello")
    end

    def push(content, **meta)
      write({ jsonrpc: "2.0", method: "notifications/claude/channel", params: { content:, meta: meta.transform_values(&:to_s) } })
    end

    # Claims the notes saved on the page as they come and pushes them into the session, for as long as
    # the process runs. The doorbell wakes it at once; it also looks every RECHECK seconds, for a note
    # whose owner went away.
    def start_pushing
      @pusher ||= Thread.new do
        Doorbell.listen(apps) do |doorbell|
          loop do
            found = @claim_lock.synchronize { claim_since(@checked_at) }
            if found.any?
              ids = found.flat_map { |_, notes| notes.map { it["id"] } }
              push("Notes the person saved on the page. They are yours: work through them one at a time with start_note and resolve_note.\n\n#{found_markdown(found)}", kind: "notes", notes: ids.join(" "))
              log("channel", Process.clock_gettime(Process::CLOCK_MONOTONIC), { content: [] }, ids)
            end
            doorbell.wait(RECHECK)
          end
        end
      rescue StandardError => error
        warn "[Tensaku] channel: #{error.class}: #{error.message}"
        @pusher = nil
      end
    end

    def cancel(id)
      @lock.synchronize { @calls.delete(id) }&.kill
    end

    # Records the call for the page, runs it, and tells the agent about notes sent since it last
    # looked: a session that has listened gets them in the answer, claimed like watch_notes would, so
    # it doesn't have to wait in watch_notes while it works. Any other session gets their ids.
    def tool_call(name, arguments)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @last = { "tool" => name.to_s, "note" => arguments["id"].presence, "at" => Time.now.utc.iso8601 }.compact
      seen!
      result = call_tool(name, arguments)
      handed = result.delete(:handed) || (news(result) unless result[:isError] || %w[list_notes watch_notes].include?(name))
      log(name, started, result, handed)
      result
    end

    def news(result)
      if @watched
        found = @claim_lock.synchronize { claim_since(@checked_at) }
        return [] if found.empty?

        result[:content] << { type: "text", text: "Notes the person saved while you worked. They are yours now; work through them next:\n\n#{found_markdown(found)}" }
        found.flat_map { |_, notes| notes.map { it["id"] } }
      else
        ids = sent_since(@checked_at).map { it["id"] }
        result[:content] << { type: "text", text: "#{ids.size == 1 ? "1 note was" : "#{ids.size} notes were"} saved on the page since you last looked (#{ids.join(", ")}). Call watch_notes or list_notes next." } if ids.any?
        []
      end
    end

    # One JSON line per tool call in each app's tmp/tensaku/mcp.log: which session, the tool, how long
    # it took, how big the answer was and the notes it handed over, to see what Tensaku costs an agent.
    def log(tool, started, result, handed)
      line = JSON.generate({
        at: Time.now.utc.iso8601(3), session: session_handle, agent: @name, tool:,
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

    # Replies are text only. A reply that repeated itself as structured data would cost an agent the
    # tokens twice, and a state change only needs an acknowledgement.
    def call_tool(name, arguments)
      case name
      when "list_notes"
        status = arguments["status"].presence || "active"
        statuses = { "active" => Notes::ACTIVE, "all" => nil }.fetch(status, status)
        @checked_at = Time.now.utc
        url = arguments["url"].presence
        text = markdown { Notes.list(url:, status: statuses, session:) }
        taken = apps.sum { |app| Tensaku.with_root(app) { Notes.list(url:, status: statuses).size - Notes.list(url:, status: statuses, session:).size } }
        text += "\n\n#{taken} more #{taken == 1 ? "note belongs" : "notes belong"} to other running agent sessions and #{taken == 1 ? "isn't" : "aren't"} listed. Leave #{taken == 1 ? "it" : "them"} to those sessions." if taken.positive?
        tool_result(text)
      when "get_note"
        app, note = find(arguments["id"])
        tool_result(Tensaku.with_root(app) { Notes.note_markdown(note, app: label(app)) })
      when "get_screenshot"
        app, _note = find(arguments["id"])
        shot = Tensaku.with_root(app) { Notes.screenshot(arguments["id"]) }
        return tool_result("Note #{arguments["id"]} has no screenshot.", error: true) unless shot

        { content: [ { type: "image", data: [ shot["png"] ].pack("m0"), mimeType: "image/png" } ], isError: false }
      when "start_note"
        note = in_app_of(arguments["id"]) { Notes.start(arguments["id"], agent: agent_label, session:) }
        tool_result("Started note #{note["id"]}. The page shows you as #{agent_label}.")
      when "resolve_note"
        note = change(arguments["id"], status: "resolved", message: arguments["reply"], started: true)
        tool_result("Resolved note #{note["id"]}.#{" Call watch_notes to keep listening." if @watched && !@channel}")
      when "decline_note"
        note = change(arguments["id"], status: "declined", message: arguments["reason"])
        tool_result("Declined note #{note["id"]}.")
      when "ask_question"
        note = change(arguments["id"], status: "question", message: arguments["question"])
        tool_result("Asked on note #{note["id"]}.")
      when "reply_to_note"
        note = change(arguments["id"], message: arguments["message"])
        tool_result("Added a message to note #{note["id"]}.")
      when "watch_notes"
        since = arguments["since"].present? ? Time.iso8601(arguments["since"]) : Time.now.utc
        timeout = arguments["timeout_seconds"].nil? ? 60 : arguments["timeout_seconds"].to_i.clamp(1, MAX_WATCH)
        first = !@watched
        @watched = true
        found, checked_at = watch(since, timeout)
        @checked_at = [ @checked_at, checked_at ].max
        text = found.empty? ? "No new notes in #{timeout}s." : found_markdown(found)
        intro = "You are listening as #{agent_label}. Tell the person this name: the page shows it, and the notes handed to you are yours.\n\n" if first
        tool_result("#{intro}#{text}\n\nchecked_at: #{checked_at.iso8601(6)}").merge(handed: found.flat_map { |_, notes| notes.map { it["id"] } })
      when "channel_ready"
        return tool_result("That isn't the code from Tensaku's channel event.", error: true) unless arguments["code"].to_s == @channel_code

        unless @channel
          @channel = true
          @watched = true
          @checked_at = Time.now.utc
          listening(+1)
          start_pushing
        end
        waiting = apps.sum { |app| Tensaku.with_root(app) { Notes.list(status: Notes::ACTIVE, session:).size } }
        tool_result("Tensaku's channel works. Notes the person saves on the page arrive in this chat as #{agent_label}, already yours. Tell the person in one line#{", and that #{waiting} earlier #{waiting == 1 ? "note is" : "notes are"} open (list_notes has them), without starting on them unless they ask" if waiting.positive?}.")
      when "current_selection"
        selection = apps.filter_map { |app| Tensaku.with_root(app) { Notes.selection } }.max_by { it["at"].to_s }
        tool_result(selection ? JSON.pretty_generate(selection) : "Nothing selected in the Tensaku overlay yet.")
      else
        tool_result("Unknown tool #{name}", error: true)
      end
    rescue Notes::NotFound, Error, ArgumentError => error
      tool_result(error.message, error: true)
    rescue StandardError => error
      warn "[Tensaku] #{error.class}: #{error.message}\n#{Array(error.backtrace).first(10).join("\n")}"
      tool_result("Tensaku hit an error: #{error.class}: #{error.message}", error: true)
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
              version = Notes.write { Notes.version }
              next if versions[app] == version

              versions[app] = version
              notes = Notes.claim_sent(since, checked_at, session:, agent: agent_label)
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
      now = Time.now.utc
      found = apps.filter_map do |app|
        notes = Tensaku.with_root(app) { Notes.claim_sent(time, now, session:, agent: agent_label) }
        [ app, notes ] if notes.any?
      end
      @checked_at = [ @checked_at, now ].max
      found
    end

    def found_markdown(found)
      found.map { |app, notes| Tensaku.with_root(app) { Notes.to_markdown(notes, app: label(app), latest: true, session:) } }.join("\n\n")
    end

    # Open notes sent after time in any app.
    def sent_since(time)
      now = Time.now.utc
      apps.flat_map { |app| Tensaku.with_root(app) { Notes.sent_between(time, now, session:) } }
    end

    def listening(change)
      @lock.synchronize { @listening += change }
      seen!
    end

    # One writer at a time, so the heartbeat can't write an old name or state over a newer one.
    def seen!
      @seen_lock.synchronize do
        each_app do
          Notes.agent_seen!(session, name: @name, handle: session_handle, listening: @listening.positive?, channel: @channel, cwd: Dir.pwd, started_at: @started_at, last: @last)
        end
      end
    rescue SystemCallError, SQLite3::BusyException
      nil # a database busy for longer than its timeout is tried again at the next heartbeat
    end

    # Two words for this session, such as amber-fox, that no other connected session of its first app
    # has. Chosen once.
    def session_handle
      @handle ||= Tensaku.with_root(apps.first) { Notes.free_handle(session) }
    end

    # Runs one tool call and returns its answer, for the `tensaku notes` command.
    def call(name, arguments = {})
      tool_call(name, arguments.transform_keys(&:to_s))
    end

    # Takes the client's name, as initialize does for an MCP client.
    def name=(name)
      @name = name.to_s
      seen!
    end

    # Takes this session off the page.
    def close
      each_app { Notes.agent_gone!(session) }
    end

    # Stops pushing notes, for tests; run stops it when stdin closes.
    def close_channel
      [ @pusher, @greeter ].compact.each(&:kill)
      @pusher = @greeter = nil
    end
    public :call, :name=, :close, :close_channel, :session_handle

    def each_app(&block)
      apps.each { |app| Tensaku.with_root(app, &block) }
    end

    def change(id, **changes)
      in_app_of(id) { Notes.update(id, agent: agent_label, session:, **changes) }
    end

    # The client's name and this session's handle, as notes and the page show it: "Claude Code · amber-fox".
    def agent_label
      "#{@name} · #{session_handle}"
    end

    def in_app_of(id, &block)
      app, = find(id)
      Tensaku.with_root(app, &block)
    end

    # The app that has the note, and the note.
    def find(id)
      apps.each do |app|
        return [ app, Tensaku.with_root(app) { Notes.find(id) } ]
      rescue Notes::NotFound
        next
      end
      raise Notes::NotFound, "No note #{id.inspect}"
    end

    # The notes the block lists in each app, as one Markdown text.
    def markdown(&block)
      parts = apps.filter_map do |app|
        Tensaku.with_root(app) do
          notes = block.call
          Notes.to_markdown(notes, app: label(app), latest: true, session:) if notes.any?
        end
      end
      parts.empty? ? "No notes." : parts.join("\n\n")
    end

    # The app's name in headings, when there is more than one app.
    def label(app)
      app.basename.to_s if apps.size > 1
    end

    def tool_result(text, error: false)
      { content: [ { type: "text", text: } ], isError: error }
    end

    def error_payload(id, code, message)
      { jsonrpc: "2.0", id:, error: { code:, message: } }
    end

    def write(payload)
      @lock.synchronize do
        @output.write(JSON.generate(payload) + "\n")
        @output.flush
      end
    rescue IOError, Errno::EPIPE
      nil
    end
  end
end
