require "json"

module Tensaku
  class Session
    # The tools an agent calls, each described for MCP's tools/list (TOOLS) and answered by the method of
    # the same name. Mcp lists them; `tensaku notes` maps its commands onto them (CLI::NOTE_COMMANDS).
    #
    # Replies are text only. A reply that repeated itself as structured data would cost an agent the
    # tokens twice, and a state change only needs an acknowledgement.
    module Tools
      BY_ID = { type: "object", properties: { id: { type: "string" } }, required: %w[id] }.freeze

      TOOLS = [
        {
          name: "list_notes",
          description: "List Tensaku notes left on pages of this Rails app. Each note has a comment and targets with the exact file and line range that rendered the element. Defaults to notes that need work (open, working and question), sent or not.",
          inputSchema: {
            type: "object",
            properties: {
              status: { type: "string", enum: %w[open working question resolved declined active archived all], description: "active (default) means open, working or question. archived lists the archive; all is every note outside it." },
              url: { type: "string", description: "Only notes left on this path, for example /about." }
            }
          }
        },
        {
          name: "get_note",
          description: "Get one Tensaku note by id.",
          inputSchema: BY_ID
        },
        {
          name: "get_screenshot",
          description: "Get the screenshot the page took of what a note points at, as a PNG, when the note says it has one. It shows the page as the person saw it when writing the note.",
          inputSchema: BY_ID
        },
        {
          name: "start_note",
          description: "Mark a note as being worked on before you make the change. The pin on the page shows that an agent has picked it up, and the note becomes this session's. Fails when the note belongs to another running agent session: then leave it. Call resolve_note as soon as the change is made.",
          inputSchema: BY_ID
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

      NAMES = TOOLS.map { it[:name] }.freeze

      private

      # Lists this session's notes. Notes another running session owns are left out and counted.
      def list_notes(arguments)
        status = arguments["status"].presence || "active"
        status = { "active" => Notes::ACTIVE, "all" => nil }.fetch(status, status)
        url = arguments["url"].presence
        @checked_at = Time.now.utc
        listed = per_app { Notes.list(url:, status:).partition { Notes.available_to?(it, id) } }
        mine = listed.map { |app, (notes, _)| [ app, notes ] }
        taken = listed.sum { |_, (_, others)| others.size }
        text = notes_markdown(mine).presence || "No notes."
        text += "\n\n#{taken} more #{taken == 1 ? "note belongs" : "notes belong"} to other running agent sessions and #{taken == 1 ? "isn't" : "aren't"} listed. Leave #{taken == 1 ? "it" : "them"} to those sessions." if taken.positive?
        result(text)
      end

      def get_note(arguments)
        app, note = Notes.locate(apps, arguments["id"])
        result(Tensaku.with_root(app) { Notes::Markdown.note(note, app: app_label(app)) })
      end

      def get_screenshot(arguments)
        shot = in_app_of(arguments["id"]) { Notes.screenshot(arguments["id"]) }
        return result("Note #{arguments["id"]} has no screenshot.", error: true) unless shot

        { content: [ { type: "image", data: [ shot["png"] ].pack("m0"), mimeType: "image/png" } ], isError: false }
      end

      def start_note(arguments)
        note = in_app_of(arguments["id"]) { Notes.start(arguments["id"], agent: label, session: id) }
        result("Started note #{note["id"]}. The page shows you as #{label}.")
      end

      def resolve_note(arguments)
        note = change(arguments["id"], status: "resolved", message: arguments["reply"], started: true)
        result("Resolved note #{note["id"]}.#{" Call watch_notes to keep listening." if @watched && !@channel}")
      end

      def decline_note(arguments)
        note = change(arguments["id"], status: "declined", message: arguments["reason"])
        result("Declined note #{note["id"]}.")
      end

      def ask_question(arguments)
        note = change(arguments["id"], status: "question", message: arguments["question"])
        result("Asked on note #{note["id"]}.")
      end

      def reply_to_note(arguments)
        note = change(arguments["id"], message: arguments["message"])
        result("Added a message to note #{note["id"]}.")
      end

      def watch_notes(arguments)
        since = arguments["since"].present? ? Time.iso8601(arguments["since"]) : Time.now.utc
        timeout = arguments["timeout_seconds"].nil? ? 60 : arguments["timeout_seconds"].to_i.clamp(1, MAX_WATCH)
        first = !@watched
        @watched = true
        found, checked_at = watch(since, timeout)
        @checked_at = [ @checked_at, checked_at ].max
        text = found.empty? ? "No new notes in #{timeout}s." : notes_markdown(found)
        intro = "You are listening as #{label}. Tell the person this name: the page shows it, and the notes handed to you are yours.\n\n" if first
        result("#{intro}#{text}\n\nchecked_at: #{checked_at.iso8601(6)}").merge(handed: ids(found))
      end

      def channel_ready(arguments)
        return result("That isn't the code from Tensaku's channel event.", error: true) unless @push && arguments["code"].to_s == channel_code

        start_channel
        waiting = per_app { Notes.list(status: Notes::ACTIVE, session: id).size }.sum(&:last)
        result("Tensaku's channel works. Notes the person saves on the page arrive in this chat as #{label}, already yours. Tell the person in one line#{", and that #{waiting} earlier #{waiting == 1 ? "note is" : "notes are"} open (list_notes has them), without starting on them unless they ask" if waiting.positive?}.")
      end

      def current_selection(_arguments)
        selection = per_app { Project.selection }.filter_map(&:last).max_by { it["at"].to_s }
        result(selection ? JSON.pretty_generate(selection) : "Nothing selected in the Tensaku overlay yet.")
      end
    end
  end
end
