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

  test "reads the Gemfile group the way Bundler does" do
    File.write(File.join(destination_root, "Gemfile"), %(source "https://rubygems.org"\ngroup(:development) do\n  if true\n    gem "puma"\n  end\n  gem "tensaku"\nend\n))

    assert_match "tensaku is in the development group", run_generator
  end

  test "an invalid .mcp.json is reported and left alone" do
    File.write(File.join(destination_root, ".mcp.json"), "{ nope")

    assert_match ".mcp.json isn't valid JSON", run_generator
    assert_file ".mcp.json", "{ nope"
  end

  test "an empty .mcp.json gets the tensaku server, and --pretend writes nothing" do
    File.write(File.join(destination_root, ".mcp.json"), "")

    run_generator [ "--pretend" ]
    assert_file ".mcp.json", ""

    run_generator
    assert_file ".mcp.json", /__tensaku\/mcp/
  end
end
