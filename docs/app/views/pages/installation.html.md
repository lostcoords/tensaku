# Installation

Tensaku is one gem in your development group. There is no JavaScript to set up.

After reading this page, you will know:

- What Tensaku needs.
- How to install it and check that it works.
- How to connect a coding agent.
- How to remove it.

## Requirements

- Ruby 4.0 or later.
- Rails 8.1.

Bundler installs Herb and ReActionView with the gem. Tensaku works with importmap, jsbundling or no JavaScript at all, because its middleware injects one prebuilt script into HTML pages.

## Install the gem

Add the gem to the development group:

```sh
bundle add tensaku --group development
```

Then restart your server. Editing and notes now work.

## Check that it works

Open a page. A round button with a red flower sits in the bottom right corner. Press <kbd>alt+shift+t</kbd> for select mode and hover an element. The label shows the file and line it came from.

### If the button doesn't appear

Tensaku only adds the overlay to full HTML pages with a 2xx or 422 status, requested from this machine. Check that:

- The server was restarted after the install and runs in development.
- The page's host is `localhost`, a `.localhost` name, a loopback IP or a name in `config.hosts`.
- The browser doesn't reach the server through a tunnel, a reverse proxy, Docker or a devcontainer.
- The response isn't streamed, compressed, sent from a file on disk or non-UTF-8.

[Safety and limits](/safety/) has the details.

## Connect a coding agent

The generator is optional. Run it to connect coding agents:

```sh
bin/rails generate tensaku:install
```

It prints every file it changes, and does this:

- Checks that Tensaku is in the development group, and warns if it isn't.
- Installs the skill in `.agents/skills/tensaku/`, and for Claude Code in `.claude/skills/tensaku/`.
- Adds `bundle exec tensaku mcp`, the MCP server, to `.mcp.json`, and to the project config of each agent below that it sets up.
- Adds `/tmp/tensaku/` to `.gitignore` unless `tmp/` is already ignored. That folder holds the page token, the write lock, the MCP log and saved screenshots. Notes aren't kept in the project; see [where notes live](/notes/#where-notes-live).

Each agent reads its own files:

| Agent | MCP entry | Skill | Checked |
|---|---|---|---|
| Claude Code | `.mcp.json` | `.claude/skills/tensaku/` | Yes, Claude Code 2.1.323 |
| Codex | `.codex/config.toml`, read once you trust the project | `.agents/skills/tensaku/` | No, from Codex's documentation |
| OpenCode | `opencode.json` | `.agents/skills/tensaku/` | No, from OpenCode's documentation |
| Cursor | `.cursor/mcp.json` | `.agents/skills/tensaku/` | No, from Cursor's documentation |
| Gemini CLI | `.gemini/settings.json` | `.agents/skills/tensaku/` | No, from Gemini CLI's documentation |
| Copilot CLI, VS Code | `.mcp.json` | `.agents/skills/tensaku/` | No, from GitHub's and VS Code's documentation |

`.mcp.json` and `.agents/skills/tensaku/` are always written. The other files are written for the agents you name, or by default for those whose config directory or file is already in the project:

```sh
bin/rails generate tensaku:install --agents codex,cursor
bin/rails generate tensaku:install --agents all
```

The generator keeps the other servers in each JSON file, and appends to `.codex/config.toml` without rewriting it. It leaves `opencode.jsonc` alone and prints the entry to add by hand.

The `.mcp.json` entry looks like this:

```json
{
  "mcpServers": {
    "tensaku": {
      "command": "bundle",
      "args": ["exec", "tensaku", "mcp"]
    }
  }
}
```

Every file the generator writes is in the project, so the MCP server and the skill load only for agents started in that project. Your agent starts the server itself, in the directory it runs in, and stops it when it quits. Claude Code asks you to approve a project's `.mcp.json` servers the first time. Restart the agent after running the generator. For another agent, add the same command to its MCP settings, or have it run `bundle exec tensaku notes`. See [the MCP server](/notes/#the-mcp-server).

## Remove Tensaku

Run `bundle remove tensaku`, then delete what the generator and your notes left behind:

- `tmp/tensaku/`
- Your notes: the `tensaku` folder in your user data folder (see [where notes live](/notes/#where-notes-live))
- `.claude/skills/tensaku/` and `.agents/skills/tensaku/`
- The `tensaku` entry in `.mcp.json`, `.codex/config.toml`, `.cursor/mcp.json`, `.gemini/settings.json` and `opencode.json`
- The `/tmp/tensaku/` lines in `.gitignore`, if the generator added them
- `config/initializers/tensaku.rb`, if you made one
