# Notes

A note is a comment attached to part of the page. Use one when the change isn't a text edit: a layout problem, a wrong value from the database, a button that should do something else.

## Leave a note

Click the corner button and choose **Select**, or press Alt+Shift+T. Hover to see where each element comes from, then click it for a menu. The arrow keys move the highlight to the parent, the first child or a sibling, Enter opens the menu, and Cmd+C (Ctrl+C) copies the highlighted element's reference when no text is selected.

- **Copy reference** copies the route, the file and line, the text, the partial chain, the Stimulus controller, the Turbo Frame and the translation key.
- **Add note** asks what should change. Select some text first to note just that text.
- **Edit text** or **Edit attributes** opens the editor.
- **Open in editor** opens the file at that line in the editor named by `RAILS_EDITOR` or `EDITOR`, through Rails' list of editors (VS Code, Cursor, Zed, RubyMine and others).

A note on selected text keeps that phrase marked on the page.

Drag in select mode to note an area. The note collects every stamped element at least half inside it.

Shift-click elements in select mode to put several of them in one note. Press **N** or **Add note** when they are all picked, or **Esc** to clear them.

## Follow up

Each note shows as a pin on the element it points at. The **Notes** panel lists the notes on the current page. From there you can copy them as Markdown, edit, move, resolve or delete them, and write to the agent. **All pages** lists the notes on every page, with a link to each. Editing a note sets it back to `open` and clears the agent's reply, so the agent picks it up again.

Each note keeps a thread: the agent's questions and messages, and your answers. Answering a question sets the note back to `open`. When a note's element is gone from the page, its card says so; **Move** points it at the element you click next.

The toolbar hides and shows the pins, and deletes every note on the page after a second click.

A note is `open`, `working` (an agent picked it up), `question` (the agent asked something back, and the question shows on the page) or `resolved`. A resolved note carries the agent's reply and its pin turns green, so you can check the change and dismiss it. Resolved notes are deleted after three days.

The page asks for the notes every four seconds while the tab is visible, so pins change as the agent works. A green light at the start of the toolbar, and on the corner button, shows that an agent called one of the MCP tools in the last 20 seconds, with its name when the agent keeps the MCP session. A toast says when an agent starts, answers or resolves a note on this page.

## Settings

The gear in the toolbar holds the settings, kept in the browser:

- **Copy notes as**: detailed (targets and thread) or one line per note.
- **Notify me**: a browser notification when an agent answers while the tab is in the background. The page then also checks every 16 seconds in the background.
- **Compact button**: the corner button stays small until you point at it.

## Where notes live

Notes are JSON files in `tmp/tensaku/notes/`, one per note. They stay on your machine, are ignored by git and are cleared by `bin/rails tmp:clear`.
