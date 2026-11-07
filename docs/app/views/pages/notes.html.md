# Notes

A note is a comment attached to part of the page. Use one when the change isn't a text edit: a layout problem, a wrong value from the database, a button that should do something else.

## Leave a note

Click the corner button and choose **Select**, or press Alt+Shift+T. Hover to see where each element comes from, then click it for a menu:

- **Copy reference** copies the route, the file and line, the text, the partial chain, the Stimulus controller, the Turbo Frame and the translation key.
- **Add note** asks what should change. Select some text first to note just that text.
- **Edit text** or **Edit attributes** opens the editor.

Drag in select mode to note an area. The note collects every stamped element at least half inside it.

Shift-click elements in select mode to put several of them in one note. Press **N** or **Add note** when they are all picked, or **Esc** to clear them.

## Follow up

Each note shows as a pin on the element it points at. The **Notes** panel lists the notes on the current page. From there you can copy them as Markdown, edit, resolve or delete them, and answer questions. Editing a note sets it back to `open` and clears the agent's reply, so the agent picks it up again.

The toolbar hides and shows the pins, and deletes every note on the page after a second click.

A note is `open`, `working` (an agent picked it up), `question` (the agent asked something back, and the question shows on the page) or `resolved`. A resolved note carries the agent's reply and its pin turns green, so you can check the change and dismiss it. Resolved notes are deleted after three days.

The page asks for the notes every four seconds while the tab is visible, so pins change as the agent works. A green light at the start of the toolbar, and on the corner button, shows that an agent called one of the MCP tools in the last 20 seconds.

## Where notes live

Notes are JSON files in `tmp/tensaku/notes/`, one per note. They stay on your machine, are ignored by git and are cleared by `bin/rails tmp:clear`.
