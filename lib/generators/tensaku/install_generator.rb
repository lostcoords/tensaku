require "rails/generators"
require "json"
require "bundler"

module Tensaku
  module Generators
    # bin/rails generate tensaku:install
    #
    # Optional: connects coding agents. Checks the Gemfile group, installs the skill, adds
    # `tensaku mcp` (a stdio MCP server) to each agent's project config and makes sure tmp/ is ignored.
    # Prints what it changed.
    #
    # .mcp.json (Claude Code, Copilot CLI) and the skill in .agents/skills (Codex, Cursor, Gemini CLI,
    # OpenCode, Copilot) are always written. The other agents' files are written for the agents named
    # with --agents, or by default for those whose config is already in the project.
    class InstallGenerator < Rails::Generators::Base
      desc "Connect coding agents to Tensaku: skill, MCP entries, gitignore check."

      AGENTS = %w[claude codex cursor gemini opencode copilot].freeze

      class_option :agents, type: :array, desc: "Agents to set up: #{AGENTS.join(", ")} or all. Defaults to Claude Code, Copilot and the agents already configured in the project."

      SKILL = File.expand_path("../../../skills/tensaku/SKILL.md", __dir__)

      def check_gemfile
        gemfile = File.join(destination_root, "Gemfile")
        return unless File.exist?(gemfile)

        groups = tensaku_groups(gemfile)
        if groups.nil?
          say_status :skip, "Couldn't read the Gemfile to check tensaku's group. Keep it in the development group.", :yellow
        elsif (groups & %i[default production]).empty?
          say_status :ok, "tensaku is in the #{groups.join(" and ")} group#{"s" if groups.size > 1}", :green
        else
          say_status :warning, "Put tensaku in the development group of your Gemfile, so production keeps " \
            "rendering with Erubi and never loads it:\n\n  group :development do\n    gem \"tensaku\"\n  end\n", :yellow
        end
      end

      def skill
        create_file ".claude/skills/tensaku/SKILL.md", File.read(SKILL) if agent?("claude")
        create_file ".agents/skills/tensaku/SKILL.md", File.read(SKILL)
      end

      COMMAND = %w[bundle exec tensaku mcp].freeze

      # Claude Code and Copilot CLI read .mcp.json.
      def mcp_json
        json_entry(".mcp.json", %w[mcpServers tensaku], { "command" => COMMAND.first, "args" => COMMAND.drop(1) })
      end

      # Codex reads .codex/config.toml in projects you trust. The table is appended as bytes, so the
      # rest of the file stays as it is.
      def codex
        return unless agent?("codex")

        path = File.join(destination_root, ".codex/config.toml")
        table = "[mcp_servers.tensaku]\ncommand = \"#{COMMAND.first}\"\nargs = #{COMMAND.drop(1).to_json}\n"
        if File.exist?(path) && File.read(path).match?(/^\s*\[mcp_servers\.tensaku\]/)
          say_status :skip, ".codex/config.toml already has [mcp_servers.tensaku]. It should read:\n\n#{table}", :blue
        elsif File.exist?(path)
          append_to_file ".codex/config.toml", "\n#{table}"
        else
          create_file ".codex/config.toml", table
        end
      end

      def cursor
        json_entry(".cursor/mcp.json", %w[mcpServers tensaku], { "command" => COMMAND.first, "args" => COMMAND.drop(1) }) if agent?("cursor")
      end

      def gemini
        json_entry(".gemini/settings.json", %w[mcpServers tensaku], { "command" => COMMAND.first, "args" => COMMAND.drop(1) }) if agent?("gemini")
      end

      # OpenCode takes the command and its arguments as one list.
      def opencode
        return unless agent?("opencode")

        if File.exist?(File.join(destination_root, "opencode.jsonc"))
          say_status :skip, "opencode.jsonc has comments Tensaku won't rewrite. Add \"tensaku\": { \"type\": \"local\", \"command\": #{COMMAND.to_json} } under \"mcp\".", :yellow
        else
          json_entry("opencode.json", %w[mcp tensaku], { "type" => "local", "command" => COMMAND }, seed: { "$schema" => "https://opencode.ai/config.json" })
        end
      end

      def gitignore
        path = File.join(destination_root, ".gitignore")
        ignored = File.exist?(path) && File.readlines(path, chomp: true).any? { it.strip.match?(%r{\A/?tmp(/|/\*|/\*\*)?\z}) }
        if ignored
          say_status :ok, "tmp/ is ignored, so tmp/tensaku/ stays out of version control", :green
        elsif File.exist?(path)
          append_to_file ".gitignore", "\n# Tensaku's token, lock, log and screenshots\n/tmp/tensaku/\n"
        else
          create_file ".gitignore", "# Tensaku's token, lock, log and screenshots\n/tmp/tensaku/\n"
        end
      end

      def done
        say "\nTensaku is ready. Start the server with bin/dev or bin/rails server, open a page, and press " \
          "Alt+Shift+T (or click the corner button)."
        say "Restart your agent so it starts tensaku mcp. Ask it to do your Tensaku notes, or to watch them " \
          "so the notes you save reach it as you write them."
        say "Codex reads .codex/config.toml once you trust the project." if agent?("codex")
      end

      private

      def agents
        @agents ||= begin
          named = Array(options[:agents]).flat_map { it.split(",") }.map(&:strip).map(&:downcase)
          if named.include?("all")
            AGENTS
          elsif named.any?
            unknown = named - AGENTS
            say_status :skip, "Unknown agents: #{unknown.join(", ")}. Known: #{AGENTS.join(", ")}", :yellow if unknown.any?
            named & AGENTS
          else
            found = { "codex" => ".codex", "cursor" => ".cursor", "gemini" => ".gemini", "opencode" => "opencode.json" }
            %w[claude copilot] + found.select { |_, path| File.exist?(File.join(destination_root, path)) }.keys
          end
        end
      end

      def agent?(name)
        agents.include?(name)
      end

      # Sets the entry at keys in a JSON file, keeping everything else. Rewriting the file is fine here:
      # these are small config files, not templates or translations.
      def json_entry(file, keys, entry, seed: {})
        path = File.join(destination_root, file)
        raw = File.exist?(path) ? File.read(path) : ""
        config = raw.strip.empty? ? seed.dup : JSON.parse(raw)
        unless config.is_a?(Hash) && (config[keys.first].nil? || config[keys.first].is_a?(Hash))
          say_status :error, "#{file} isn't a JSON object with an object at #{keys.first}. Add the tensaku server to it by hand.", :red
          return
        end

        parent = (config[keys.first] ||= {})
        if parent[keys.last] == entry
          say_status :identical, file, :blue
          return
        end

        parent[keys.last] = entry
        create_file file, JSON.pretty_generate(config) + "\n", force: true, verbose: false
        say_status :update, "#{file} (tensaku: #{COMMAND.join(" ")})", :green
      rescue JSON::ParserError => error
        say_status :error, "#{file} isn't valid JSON (#{error.message.lines.first.strip}). Fix it, or add the tensaku server by hand.", :red
      end

      # The groups tensaku is listed in, read the way Bundler reads the Gemfile, or nil when it isn't
      # listed or the Gemfile can't be evaluated here.
      def tensaku_groups(gemfile)
        dsl = Bundler::Dsl.new
        Dir.chdir(destination_root) { dsl.eval_gemfile(gemfile) }
        dsl.dependencies.find { it.name == "tensaku" }&.groups&.map(&:to_sym)
      rescue StandardError, ScriptError
        nil
      end
    end
  end
end
