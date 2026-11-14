module Tensaku
  module Notes
    # Notes as an agent reads them: the MCP tools' answers, `tensaku notes` and the page's copy button.
    module Markdown
      module_function

      # app names the app in each heading, for an agent that sees notes from several apps. With
      # latest: true each thread is cut down to what is new (see latest_thread). session, the agent
      # session the list is for, adds whether each note is its own. absolute: true gives file paths from
      # the filesystem root, which an agent can open without looking for the app first.
      def list(notes, app: nil, latest: false, session: nil, absolute: false)
        notes = Array(notes)
        return "No notes." if notes.empty?

        base = Project.base_url
        notes.map { note(it, base:, app:, latest:, session:, absolute:) }.join("\n\n")
      end

      # One line per note, for a chat where the detailed form is too long.
      def short(notes)
        notes = Array(notes)
        return "No notes." if notes.empty?

        notes.map do |note|
          where = Array(note["targets"]).filter_map { [ it["file"], it["range"]&.split("-")&.first ].compact.join(":").presence }.uniq.first(3)
          "- `#{note["id"]}` (#{note["status"]}) #{note["comment"].squish.truncate(160)}#{" at #{where.map { "`#{it}`" }.join(", ")}" if where.any?}"
        end.join("\n")
      end

      def note(note, base: Project.base_url, app: nil, latest: false, session: nil, absolute: false)
        page = base && note["url"].to_s.start_with?("/") ? "#{base.chomp("/")}#{note["url"]}" : note["url"]
        lines = [ "## Tensaku note #{note["id"]} (#{note["status"]}) on #{page}#{" in #{app}" if app}", "" ]
        if session && ACTIVE.include?(note["status"])
          lines << if note["session"] == session && note["status"] == "working" then "*Yours, and started: make the change, then resolve it.*"
          elsif note["session"] == session then "*Yours. Call start_note before you change anything.*"
          elsif note["stopped"] then "*Its session stopped while working on it, so it is nobody's now. Part of the change may already be made: check the file before you redo it. Call start_note to take it.*"
          else "*Nobody's yet: call start_note before you work on it, so no other session takes it.*"
          end
          lines << ""
        end
        lines << note["comment"]
        targets = Array(note["targets"])
        if targets.any?
          lines << ""
          targets.each { lines << "- #{target(it, absolute:)}" }
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

      # A long back-and-forth repeated on every watch_notes call costs the agent its context, so a list
      # keeps the agent's latest message and everything after it, and says how many came before.
      def latest_thread(thread)
        last_agent = thread.rindex { it["from"] == "agent" }
        kept = last_agent ? thread[last_agent..] : thread.last(2)
        [ thread.size - kept.size, kept ]
      end

      def target(target, absolute: false)
        file = target["file"] && absolute ? Tensaku.root.expand_path.join(target["file"]).to_s : target["file"]
        location = [ file, target["range"] ].compact.join(":")
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
    end
  end
end
