---
name: tensaku
description: Work through Tensaku notes, the comments a person left on pages of this Rails app in development, each pointing at the exact file and line that rendered the element. Use when the user mentions Tensaku, notes on the page, "my notes", asks you to go through what they marked up in the browser, or asks you to watch or listen for their notes.
---

# Tensaku notes

Tensaku is a development-only overlay for this Rails app. The person clicks an element (or drags over an
area) on a running page and writes what should change. Each note records the page URL, the comment, and
one or more targets with the source position Herb stamped on the element.

## Finding notes

Use whichever is available, in this order:

1. **MCP**: the `tensaku` server (`bundle exec tensaku mcp`, started from the project's MCP config).
   Tools: `list_notes`, `get_note`, `get_screenshot`, `start_note`, `resolve_note`, `decline_note`, `reply_to_note`,
   `ask_question`, `watch_notes`, `channel_ready`, `current_selection`. It reads Tensaku's database, so the dev server
   doesn't have to be running.
2. **Command line**: `bundle exec tensaku notes`, when the MCP server isn't configured. It does what the
   tools do and prints the same text: `tensaku notes` lists the open notes, then `tensaku notes start
   ID`, `resolve ID REPLY`, `decline ID REASON`, `ask ID QUESTION`, `reply ID MESSAGE`, `show ID`,
   `screenshot ID` (saves the note's screenshot as a PNG and prints where) and `watch`. Pass `--as NAME`
   with your name, so the page shows who is working.

A note looks like this:

```json
{
  "id": "a7f3",
  "url": "/about",
  "comment": "tighten this, and the heading is wrong",
  "targets": [
    { "kind": "element", "file": "app/views/pages/_hero.html.erb", "range": "4:3-4:40", "tag": "h1", "text": "About me",
      "classes": ["hero__title", "text-4xl"],
      "context": { "partials": ["app/views/pages/_hero.html.erb", "app/views/pages/about.html.erb"], "controller": "hero" } },
    { "kind": "translation", "key": "pages.about.title", "locale": "en", "file": "config/locales/en.yml", "range": "12" }
  ],
  "rect": { "x": 120, "y": 340, "width": 600, "height": 180 },
  "status": "open",
  "sent_at": "2026-11-10T09:12:00.000000Z",
  "thread": []
}
```

- `sent_at` is when the person last saved, edited or answered the note.
- `classes` are the element's own CSS classes, for notes about how something looks.

- `range` is `line:column-line:column` in `file` (1-based). For translations it's the line of the key. It's
  from when the note was written: if the file has changed since, look for the target's `text` in it.
- `kind` is `element`, `text` (the person selected that text), `translation` (the text came from that
  I18n key) or `markdown` (a Markdown source block).
- `rect` is set for area notes: the person dragged over a region, and `targets` lists the elements in it.
- An element rendered in a loop or a repeated partial has one source position for every copy.
- Text from Ruby (`<%= @post.title %>`) points at the ERB expression; the data itself lives elsewhere.

## Working through notes

1. List the open notes (`list_notes`, or `tensaku notes`). Each is marked *Yours* or *Nobody's yet*;
   notes other sessions hold aren't listed.
2. Call `start_note` on a note you took from `list_notes`, before you change anything, so the person
   sees it's being worked on and no other session takes it. If it fails, leave that note. Notes handed
   to you by `watch_notes`, a channel event or another tool's answer are already started: skip
   `start_note` for them. `resolve_note` refuses a note that isn't started for you, and a note the
   person took back from you. A note marked as stopped was
   started by a session that ended: part of its change may already be in the file. Then open the
   target file at the range, read the comment, and make the change. Notes from the MCP tools and
   `tensaku notes` give the file's absolute path, so open it directly instead of searching for it, and
   read it in the same turn as `start_note` when you need one. Look at
   `context.partials` when the fix belongs in a parent template, and at the translation target when the
   text comes from a locale file (change every locale that needs it).
3. Read the note's `thread`: the person's answers to earlier questions are there. Use `reply_to_note`
   to say what you found when that helps the person. If the comment is ambiguous, don't guess: call `ask_question` with a short, specific question. The
   question shows on the page and the note waits for an answer.
4. As soon as the change is made, call `resolve_note` with a one-line reply that says what changed and
   where, for example `Shortened the intro in app/views/pages/_hero.html.erb:6`. The pin on the page
   turns green so the person can check it.
5. If the change shouldn't be made (it would break something, or belongs somewhere else), call
   `decline_note` with the reason instead of resolving it.

If `start_note` says a note belongs to another agent session, leave that note and take the next. When
you start watching, tell the person the session name the first `watch_notes` answer gives you (such as
amber-fox): the page shows it next to your name.

Take the notes one at a time, and resolve each before you start the next. The person is watching the page,
so don't make every change first and update the notes at the end. These calls are small: `start_note` and
`resolve_note` answer with one line. `list_notes` already has each note's text, so don't call
`get_note` after it, unless a thread says earlier messages were left out and you need them. The answer
of `resolve_note`, `decline_note` and `ask_question` says how many open notes are left, so don't list
again to find out.

In Claude Code, Tensaku may arrive as a channel: a `<channel source="tensaku">` message asks you to
call `channel_ready` with a code, and later ones hold notes the person saved, already yours. Work
through those like notes from `watch_notes`; there's no need to call `watch_notes` then.

Once you have called `watch_notes`, notes the person saves while you work come with the answer of
your next Tensaku call ("Notes the person saved while you worked"), already yours: work through them
after the current note. Call `watch_notes` again only when you have nothing else to do. When an answer
ends with "notes were saved on the page since you last looked", call `watch_notes` or `list_notes`
after finishing the current note.

When the person asks you to watch or listen for their notes, call `watch_notes` in a loop: work through
the notes it returns, then call it again, passing the `checked_at` line of the previous answer as
`since`. When it times out with no notes, call it again. The page shows you as listening while you
wait, and the notes they save reach you as they write them. Stop when they ask you to.

A note that says "Screenshot:" has a picture of what it points at, as the page looked when the person
wrote it. Get it with `get_screenshot` (or `tensaku notes screenshot ID`) when the comment is about how
something looks.
