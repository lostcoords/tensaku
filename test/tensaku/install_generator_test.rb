require "test_helper"
require "rails/generators/test_case"
require "generators/tensaku/install_generator"

class Tensaku::InstallGeneratorTest < Rails::Generators::TestCase
  tests Tensaku::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator", __dir__)
  setup :prepare_destination

  test "sets up the initializer, skill, MCP entry and gitignore, keeping other MCP servers" do
    File.write(File.join(destination_root, "Gemfile"), %(source "https://rubygems.org"\ngroup :development do\n  gem "tensaku"\nend\n))
    File.write(File.join(destination_root, ".mcp.json"), JSON.generate(mcpServers: { other: { command: "x" } }))

    output = run_generator([ "--port", "4000" ])

    assert_match "tensaku is in the development group", output
    assert_file "config/initializers/reactionview.rb", /ReActionView.configure/
    assert_file ".claude/skills/tensaku/SKILL.md", /name: tensaku/
    assert_file ".mcp.json" do |content|
      servers = JSON.parse(content)["mcpServers"]
      assert_equal({ "command" => "x" }, servers["other"])
      assert_equal({ "type" => "http", "url" => "http://localhost:4000/__tensaku/mcp" }, servers["tensaku"])
    end
    assert_file ".gitignore", %r{/tmp/tensaku/}
  end

  test "warns when tensaku isn't in the development group and leaves an ignored tmp alone" do
    File.write(File.join(destination_root, "Gemfile"), %(source "https://rubygems.org"\ngem "tensaku"\n))
    File.write(File.join(destination_root, ".gitignore"), "/tmp/*\n")

    output = run_generator

    assert_match "Put tensaku in the development group", output
    assert_file ".gitignore", "/tmp/*\n"
  end
end
