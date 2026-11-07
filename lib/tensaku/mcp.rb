require "json"

module Tensaku
  # A small MCP server (Streamable HTTP transport, JSON responses, no sessions) on the dev server, so
  # an agent can read and resolve notes. Configure it in .mcp.json as an http server at
  # http://localhost:3000/__tensaku/mcp.
  class Mcp
    PROTOCOL_VERSIONS = %w[2025-11-25 2025-06-18 2025-03-26 2024-11-05].freeze
    MAX_WATCH = 300

    TOOLS = [
      {
        name: "list_notes",
        description: "List Tensaku notes left on pages of this Rails app. Each note has a comment and targets with the exact file and line range that rendered the element. Defaults to notes that need work (open, working and question).",
        inputSchema: {
          type: "object",
          properties: {
            status: { type: "string", enum: %w[open working question resolved active all], description: "active (default) means open, working or question." },
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
        name: "start_note",
        description: "Mark a note as being worked on before you make the change. The pin on the page shows that an agent has picked it up. Resolve it with resolve_note when done.",
        inputSchema: { type: "object", properties: { id: { type: "string" } }, required: [ "id" ] }
      },
      {
        name: "resolve_note",
        description: "Mark a note resolved after making the change. The reply is shown on the page next to a green pin, so say briefly what changed and where (for example: changed the heading in app/views/pages/_hero.html.erb:4).",
        inputSchema: { type: "object", properties: { id: { type: "string" }, reply: { type: "string" } }, required: %w[id reply] }
      },
      {
        name: "ask_question",
        description: "Ask the person who wrote a note for clarification instead of guessing. The question shows on the page; the note's status becomes question until they answer by editing the note.",
        inputSchema: { type: "object", properties: { id: { type: "string" }, question: { type: "string" } }, required: %w[id question] }
      },
      {
        name: "watch_notes",
        description: "Wait for new or changed open notes, so you can work through notes as they are added. Returns as soon as there are any, or empty after the timeout. Pass the checked_at value of the previous call as since so nothing is missed.",
        inputSchema: {
          type: "object",
          properties: {
            since: { type: "string", description: "ISO 8601 time. Defaults to now." },
            timeout_seconds: { type: "integer", minimum: 1, maximum: MAX_WATCH, description: "Defaults to 60." }
          }
        }
      },
      {
        name: "current_selection",
        description: "What the person last selected in the Tensaku overlay (elements with file and line), for questions like 'what is this?'.",
        inputSchema: { type: "object", properties: {} }
      }
    ].freeze

    def call(request)
      return [ 405, { "allow" => "POST" }, [ "" ] ] unless request.post?

      message = JSON.parse(request.body.read.to_s)
      responses = Array.wrap(message).filter_map { respond(it) }
      return [ 202, {}, [ "" ] ] if responses.empty?

      payload = message.is_a?(Array) ? responses : responses.first
      [ 200, { "content-type" => "application/json" }, [ JSON.generate(payload) ] ]
    rescue JSON::ParserError
      [ 400, { "content-type" => "application/json" }, [ JSON.generate(error_payload(nil, -32700, "Parse error")) ] ]
    end

    private

    def respond(message)
      id = message["id"]
      return nil if id.nil? # a notification

      result = case message["method"]
      when "initialize" then initialize_result(message.dig("params", "protocolVersion"))
      when "ping" then {}
      when "tools/list" then { tools: TOOLS }
      when "tools/call" then Notes.agent_seen!.then { call_tool(message.dig("params", "name"), message.dig("params", "arguments") || {}) }
      else return error_payload(id, -32601, "Method not found: #{message["method"]}")
      end
      { jsonrpc: "2.0", id:, result: }
    end

    def initialize_result(requested)
      {
        protocolVersion: PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSIONS.first,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "tensaku", version: Tensaku::VERSION },
        instructions: "Tensaku notes are comments a person left on pages of this Rails app, each with the file and line that rendered the element. Act on open notes, then resolve each with a short reply, or ask a question when a note is unclear."
      }
    end

    def call_tool(name, arguments)
      case name
      when "list_notes"
        status = arguments["status"].presence || "active"
        statuses = { "active" => Notes::ACTIVE, "all" => nil }.fetch(status, status)
        notes = Notes.list(url: arguments["url"].presence, status: statuses)
        tool_result(Notes.to_markdown(notes), notes:, checked_at: Time.now.utc.iso8601)
      when "get_note"
        note = Notes.find(arguments["id"])
        tool_result(Notes.note_markdown(note), note:)
      when "start_note"
        note = Notes.update(arguments["id"], status: "working")
        tool_result("Started note #{note["id"]}. Resolve it with resolve_note when the change is made.", note:)
      when "resolve_note"
        note = Notes.update(arguments["id"], status: "resolved", reply: arguments["reply"])
        tool_result("Resolved note #{note["id"]}.", note:)
      when "ask_question"
        note = Notes.update(arguments["id"], status: "question", reply: arguments["question"])
        tool_result("Asked on note #{note["id"]}. It shows on the page until the person answers.", note:)
      when "watch_notes"
        since = arguments["since"].present? ? Time.iso8601(arguments["since"]) : Time.now.utc
        timeout = arguments["timeout_seconds"].to_i.clamp(1, MAX_WATCH)
        timeout = 60 if arguments["timeout_seconds"].nil?
        notes = Notes.watch(since:, timeout:)
        text = notes.empty? ? "No new notes in #{timeout}s. Call watch_notes again to keep waiting." : Notes.to_markdown(notes)
        tool_result(text, notes:, checked_at: Time.now.utc.iso8601)
      when "current_selection"
        selection = Endpoints.selection
        tool_result(selection ? JSON.pretty_generate(selection) : "Nothing selected in the Tensaku overlay yet.", selection:)
      else
        tool_result("Unknown tool #{name}", error: true)
      end
    rescue Notes::NotFound, Error, ArgumentError => error
      tool_result(error.message, error: true)
    end

    def tool_result(text, error: false, **structured)
      { content: [ { type: "text", text: } ], structuredContent: structured.presence, isError: error }.compact
    end

    def error_payload(id, code, message)
      { jsonrpc: "2.0", id:, error: { code:, message: } }
    end
  end
end
