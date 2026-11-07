require "rails/generators"
require "json"

module Tensaku
  module Generators
    # bin/rails generate tensaku:install
    #
    # Checks the Gemfile group, writes the ReActionView initializer, installs the Claude Code skill,
    # adds the MCP endpoint to .mcp.json and makes sure tmp/ is ignored. Prints what it changed.
    class InstallGenerator < Rails::Generators::Base
      desc "Set up Tensaku: ReActionView initializer, Claude Code skill, .mcp.json entry, gitignore check."

      class_option :port, type: :numeric, default: 3000, desc: "Port of the development server, for .mcp.json"

      SKILL = File.expand_path("../../../skills/tensaku/SKILL.md", __dir__)

      def check_gemfile
        gemfile = File.join(destination_root, "Gemfile")
        return unless File.exist?(gemfile)

        if development_only?(File.read(gemfile))
          say_status :ok, "tensaku is in the development group", :green
        else
          say_status :warning, "Put tensaku in the development group of your Gemfile, so production keeps " \
            "rendering with Erubi and never loads it:\n\n  group :development do\n    gem \"tensaku\"\n  end\n", :yellow
        end
      end

      def reactionview_initializer
        path = "config/initializers/reactionview.rb"
        if File.exist?(File.join(destination_root, path))
          say_status :exist, "#{path} (Tensaku turns on intercept_erb and source attribution itself)", :blue
          return
        end

        create_file path, <<~RUBY
          # ReActionView renders ERB with Herb in development. Tensaku turns on ERB interception and adds
          # Herb's source attribution itself; the options here are ReActionView's own.
          # It's only loaded in development (it comes with Tensaku, in the development group).
          if defined?(ReActionView)
            ReActionView.configure do |config|
              # Herb's dev tools (outlines, Open in Editor). They wrap ERB output in display: contents spans.
              config.debug_mode = true
            end
          end
        RUBY
      end

      def skill
        create_file ".claude/skills/tensaku/SKILL.md", File.read(SKILL)
      end

      def mcp_json
        path = File.join(destination_root, ".mcp.json")
        config = File.exist?(path) ? JSON.parse(File.read(path)) : {}
        servers = (config["mcpServers"] ||= {})
        entry = { "type" => "http", "url" => "http://localhost:#{options[:port]}/__tensaku/mcp" }
        if servers["tensaku"] == entry
          say_status :identical, ".mcp.json", :blue
          return
        end

        servers["tensaku"] = entry
        File.write(path, JSON.pretty_generate(config) + "\n")
        say_status :update, ".mcp.json (tensaku: #{entry["url"]})", :green
      end

      def gitignore
        path = File.join(destination_root, ".gitignore")
        ignored = File.exist?(path) && File.readlines(path, chomp: true).any? { it.strip.match?(%r{\A/?tmp(/|/\*|/\*\*)?\z}) }
        if ignored
          say_status :ok, "tmp/ is ignored, so notes stay local", :green
        elsif File.exist?(path)
          append_to_file ".gitignore", "\n# Tensaku notes\n/tmp/tensaku/\n"
        else
          create_file ".gitignore", "# Tensaku notes\n/tmp/tensaku/\n"
        end
      end

      def done
        say "\nTensaku is ready. Start the server with bin/dev or bin/rails server, open a page, and press " \
          "Alt+Shift+T (or click the corner button)."
      end

      private

      def development_only?(gemfile)
        lines = gemfile.lines
        index = lines.index { it.match?(/^\s*gem\s+["']tensaku["']/) }
        return false unless index
        return true if lines[index].match?(/group:\s*(:development|\[\s*:development\s*\])/)

        inside = false
        lines.each_with_index do |current, number|
          inside = true if current.match?(/^\s*group\s+:development\s+do/)
          return true if inside && number == index
          inside = false if inside && current.match?(/^\s*end\b/)
        end
        false
      end
    end
  end
end
