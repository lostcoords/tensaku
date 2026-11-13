# Tensaku

Tensaku (添削, correcting a draft) lets you click text on a running Rails page and edit it. It writes the change back to the ERB template, the locale YAML or the Markdown file. For anything that isn't a text edit, leave a note on the page, and your coding agent reads it with the file and line of each element.

Tensaku runs only in development, on [Herb](https://github.com/marcoroth/herb) through [ReActionView](https://github.com/marcoroth/reactionview). Test and production keep rendering with Erubi and never load Tensaku, ReActionView or Herb.

It needs Ruby 4.0 or later and Rails 8.1.

## Try it here

The [home page](/) runs Tensaku's overlay in your browser, so you can edit text and leave notes there without installing anything. A stand-in answers the overlay's requests, so nothing leaves the browser and no file changes.

To try it on real files, clone the repository and run `bin/rails server` in `docs/`. You can then edit every paragraph on these pages. They are Markdown files that Kiln renders.

## Where to start

- [Install Tensaku](/installation/) with one command.
- Read [what can be edited](/editing/) and how a save works.
- Leave [notes](/notes/), and see [how agents read them](/notes/#how-agents-read-notes).
- Read [safety and limits](/safety/) before you use it on a real app.
