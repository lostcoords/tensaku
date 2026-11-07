# Notes

A note is a comment attached to part of the page. Use one when the change isn't a text edit: a layout problem, a wrong value from the database, a button that should do something else.

## Leave a note

Click the corner button and choose **Select**, or press Alt+Shift+T. Hover to see where each element comes from, then click it for a menu:

- **Copy reference** copies the route, the file and line, the text, the partial chain, the Stimulus controller, the Turbo Frame and the translation key.
- **Add note** asks what should change. Select some text first to note just that text.
- **Edit text** or **Edit attributes** opens the editor.

Drag in select mode to note an area. The note collects every stamped element at least half inside it.

## Follow up

Each note shows as a pin on the element it points at. The **Notes** panel lists the notes on the current page. From there you can copy them as Markdown, resolve or delete them, and answer questions.

A note is `open`, `question` (the agent asked something back, and the question shows on the page) or `resolved`. A resolved note carries the agent's reply and its pin turns green, so you can check the change and dismiss it. Resolved notes are deleted after three days.

## Where notes live

Notes are JSON files in `tmp/tensaku/notes/`, one per note. They stay on your machine, are ignored by git and are cleared by `bin/rails tmp:clear`.
