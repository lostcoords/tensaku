require "json"

module Tensaku
  # The MCP server an agent starts with `tensaku mcp`: newline-delimited JSON-RPC over stdin and stdout,
  # in front of one Session. The dev server doesn't have to be running and no port is configured.
  #
  # Claude Code channels: the server declares the experimental claude/channel capability, which lets it
  # push a message into a Claude Code session started with
  # `claude --dangerously-load-development-channels server:tensaku`; the message starts a turn as if the
  # person had typed it. A session without the flag drops these messages without an error, so the
  # server first sends a hello with a code and the session only treats the channel as working once
  # Claude calls channel_ready with that code (see Session).
  class Mcp
    PROTOCOL_VERSIONS = %w[2025-11-25 2025-06-18 2025-03-26 2024-11-05].freeze

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
            timeout_seconds: { type: "integer", minimum: 1, maximum: Session::MAX_WATCH, description: "Defaults to 60." }
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

    # Claude Code registers its channel listener a moment after initialization, and drops what comes
    # before it (seen in its debug log), so the hello waits, and is sent once more until answered.
    HELLO_AFTER = [ 1.5, 6 ].freeze

    attr_reader :session

    # apps are the root directories of the Rails apps to serve.
    def initialize(apps, output: $stdout)
      @output = output
      @session = Session.new(apps, push: method(:push))
      @lock = Mutex.new
      @calls = {}
      @claude = false
    end

    # Reads requests until stdin closes. Tool calls run in threads of their own, so a waiting
    # watch_notes doesn't hold up other requests and can be cancelled.
    def run(input = $stdin)
      heartbeat = session.heartbeat
      input.each_line do |line|
        next if line.strip.empty?

        handle(line)
      end
    ensure
      heartbeat&.kill
      close
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

    # Stops the hello and the tool calls still running, and the session's channel.
    def close
      @greeter&.kill
      @greeter = nil
      @lock.synchronize { @calls.values }.each(&:kill)
      session.close
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
      when "tools/call" then session.call(message.dig("params", "name"), message.dig("params", "arguments") || {})
      else return error_payload(id, -32601, "Method not found: #{message["method"]}")
      end
      { jsonrpc: "2.0", id:, result: }
    end

    def initialize_result(params)
      client = params["clientInfo"].to_h
      session.name = (client["title"].presence || client["name"].presence || session.name).to_s.truncate(80)
      # Channels are Claude Code's; other clients get neither the capability nor the hello.
      @claude = [ client["name"], client["title"] ].any? { it.to_s.match?(/claude/i) }
      session.seen!
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

    def greet
      return unless @claude

      @greeter ||= Thread.new { HELLO_AFTER.each { sleep it; hello } }
    end

    # The first channel message. A session that loaded the channel gets it as a turn and calls
    # channel_ready; any other drops it.
    def hello
      return if session.channel?

      push("Tensaku is connected as #{session.label}. To have the person's notes pushed into this chat as they save them, call the channel_ready tool with code #{session.channel_code}, then tell the person in one line that their Tensaku notes now arrive here.", kind: "hello")
    end

    def push(content, **meta)
      write({ jsonrpc: "2.0", method: "notifications/claude/channel", params: { content:, meta: meta.transform_values(&:to_s) } })
    end

    def cancel(id)
      @lock.synchronize { @calls.delete(id) }&.kill
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
