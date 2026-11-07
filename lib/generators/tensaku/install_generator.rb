require "rails/generators"
require "json"
require "bundler"

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
              # Herb's dev tools (outlines, Open in Editor) are on by default in development. Tensaku
              # doesn't need them. Their script also waits for Herb's dev server, which only runs with
              # `slots`, and warns when nothing listens on its port.
              config.debug_mode = false
            end
          end
        RUBY
      end

      def skill
        create_file ".claude/skills/tensaku/SKILL.md", File.read(SKILL)
      end

      def mcp_json
        path = File.join(destination_root, ".mcp.json")
        raw = File.exist?(path) ? File.read(path) : ""
        config = raw.strip.empty? ? {} : JSON.parse(raw)
        unless config.is_a?(Hash)
          say_status :error, ".mcp.json isn't a JSON object. Add the tensaku server to it by hand.", :red
          return
        end

        servers = (config["mcpServers"] ||= {})
        entry = { "type" => "http", "url" => "http://localhost:#{options[:port]}#{Tensaku.config.mount_path}/mcp" }
        if servers["tensaku"] == entry
          say_status :identical, ".mcp.json", :blue
          return
        end

        servers["tensaku"] = entry
        create_file ".mcp.json", JSON.pretty_generate(config) + "\n", force: true, verbose: false
        say_status :update, ".mcp.json (tensaku: #{entry["url"]})", :green
      rescue JSON::ParserError => error
        say_status :error, ".mcp.json isn't valid JSON (#{error.message.lines.first.strip}). Fix it, or add the tensaku server by hand.", :red
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
