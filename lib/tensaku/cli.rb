require "pathname"

module Tensaku
  # The `tensaku` command. `tensaku mcp` is the MCP server an agent starts over stdio. It loads Tensaku
  # and Active Support but not the Rails app, so the dev server doesn't need to be running.
  module CLI
    USAGE = <<~TEXT
      Usage: bundle exec tensaku mcp [--app PATH]...
             bundle exec tensaku notes [COMMAND] [--app PATH]... [--as NAME]

      tensaku mcp runs Tensaku's MCP server over stdin and stdout. Coding agents start it from their
      project config, such as .mcp.json; `bin/rails generate tensaku:install` writes those entries.

      tensaku notes does what the MCP tools do, for an agent without MCP:

        tensaku notes [--status STATUS] [--url PATH]   list notes (open, working and question by default;
                                                        STATUS is one of those, resolved, declined,
                                                        active, archived or all)
        tensaku notes show ID                           one note with its whole thread
        tensaku notes screenshot ID [FILE]              save the note's screenshot as a PNG (default:
                                                        tmp/tensaku/screenshots/ID.png in its app)
        tensaku notes start ID                          mark it as being worked on
        tensaku notes resolve ID REPLY                  mark it resolved, with a one-line reply
        tensaku notes decline ID REASON                 close it without a change
        tensaku notes ask ID QUESTION                   ask the person something
        tensaku notes reply ID MESSAGE                  add a message to its thread
        tensaku notes watch [--since TIME] [--timeout SECONDS]
                                                        wait for notes the person sends (60 seconds by
                                                        default, up to 300)

      --as NAME is the name the page shows for you (default: tensaku CLI).

      Both serve the notes of the Rails app that contains the current directory. Run from a directory
      that isn't inside an app, they serve the apps up to two levels below that list tensaku in their
      Gemfile.lock. --app PATH picks an app, and can be given more than once.
    TEXT

    NOTE_COMMANDS = {
      "show" => [ "get_note", %w[id] ],
      "start" => [ "start_note", %w[id] ],
      "resolve" => [ "resolve_note", %w[id reply] ],
      "decline" => [ "decline_note", %w[id reason] ],
      "ask" => [ "ask_question", %w[id question] ],
      "reply" => [ "reply_to_note", %w[id message] ]
    }.freeze

    # Directories skipped when looking for apps below the current directory.
    SKIP = %w[node_modules vendor tmp log test spec].freeze

    module_function

    def start(argv, input: $stdin, output: $stdout)
      command, *rest = argv
      return output.puts(USAGE) unless %w[mcp notes].include?(command)

      apps = apps(rest)
      return abort("tensaku: no Rails app with tensaku found from #{Dir.pwd}. Pass --app PATH.") if apps.empty?

      load_mcp
      return notes(rest, apps, output:) if command == "notes"

      output.sync = true
      Mcp.new(apps, output:).run(input)
    end

    # One `tensaku notes` command, run as a session of its own that leaves when it's done. Prints the
    # same text as the MCP tool, and exits 1 when the tool failed.
    def notes(args, apps, output: $stdout)
      options, words = options(args)
      return screenshot(words[1], words[2], apps, output:) if words.first == "screenshot" && words[1]

      name, arguments = note_call(words, options)
      return output.puts(USAGE) unless name

      server = Mcp.new(apps, output: nil)
      server.name = options["as"] || "tensaku CLI"
      result = server.call(name, arguments)
      output.puts(result[:content].map { it[:text] }.join("\n\n"))
      exit(1) if result[:isError]
    ensure
      server&.close
    end

    # Writes a note's screenshot to file, for an agent that reads images from disk, and prints where.
    def screenshot(id, file, apps, output:)
      app = apps.find { |root| Tensaku.with_root(root) { Notes.find(id) } rescue Notes::NotFound }
      abort "No note #{id.inspect}" unless app

      shot = Tensaku.with_root(app) { Notes.screenshot(id) } or abort "Note #{id} has no screenshot."
      path = Pathname(file || app.join("tmp/tensaku/screenshots/#{id}.png")).expand_path
      path.dirname.mkpath
      path.binwrite(shot["png"])
      output.puts("#{path} (#{shot["width"]}x#{shot["height"]})")
    end

    def note_call(words, options)
      subcommand, *values = words
      return [ "list_notes", options.slice("status", "url") ] if subcommand.nil?
      return [ "watch_notes", { "since" => options["since"], "timeout_seconds" => options["timeout"]&.to_i }.compact ] if subcommand == "watch"

      tool, params = NOTE_COMMANDS[subcommand]
      return nil unless tool && values.size >= params.size

      [ tool, params.each_with_index.to_h { |param, i| [ param, i == params.size - 1 ? values[i..].join(" ") : values[i] ] } ]
    end

    # Splits --flag VALUE pairs from the other words. --app is read by apps.
    def options(args)
      options = {}
      words = []
      args = args.dup
      while (arg = args.shift)
        if arg.start_with?("--")
          options[arg.delete_prefix("--")] = args.shift
        else
          words << arg
        end
      end
      [ options.except("app"), words ]
    end

    # The app roots to serve: those passed with --app, else the app containing pwd, else apps below it.
    def apps(args, pwd: Pathname(Dir.pwd))
      pwd = pwd.expand_path
      named = args.each_cons(2).select { |flag, _| flag == "--app" }.map { |_, path| pwd.join(path).expand_path }
      return named if named.any?

      inside = pwd.ascend.find { app?(it) }
      return [ inside ] if inside

      [ "*", "*/*" ].flat_map { pwd.glob("#{it}/config/application.rb") }
        .map { it.dirname.dirname }
        .reject { |root| root.relative_path_from(pwd).each_filename.any? { SKIP.include?(it) || it.start_with?(".") } }
        .select { uses_tensaku?(it) }
        .sort
    end

    def app?(dir)
      dir.join("config/application.rb").file?
    end

    def uses_tensaku?(root)
      lock = root.join("Gemfile.lock")
      lock.file? && lock.read.match?(/^    tensaku \(/)
    end

    def load_mcp
      require "active_support"
      require "active_support/core_ext/object/blank"
      require "active_support/core_ext/string/filters"
      require "active_support/core_ext/hash/keys"
      require "active_support/core_ext/enumerable"
      require "tensaku"
    end
  end
end
