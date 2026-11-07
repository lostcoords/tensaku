# Tensaku

Tensaku edits text on a running Rails page in development and writes it back to the source, and keeps
notes for coding agents. Use jj for version control; never use mutating Git commands.

- Read PLAN.md before design changes. Its decisions log is the reference for what Tensaku does and
  leaves out. ART_STYLE.md is the direction for the visual design pass.
- Nothing may change outside development: no loading Herb, ReActionView or Tensaku code in test or
  production (`test/tensaku/production_test.rb` checks it). New code goes behind the railtie's
  development check or Tensaku's autoloads.
- Writes are byte splices with a stale check. Never load and dump YAML, never re-serialize a template.
  Every new splice needs a test that the rest of the file is unchanged.
- The overlay source is `app/javascript/tensaku/*.ts`. Run `bun run build` and commit
  `app/assets/tensaku.js`; `bin/lint` fails when it's out of date.
- The test suite runs `test/dummy` in development. Browser tests write to dummy files and restore them.
- `docs/` is the documentation site, a separate Rails app with its own Gemfile (Kiln content layer,
  lostcoords-ui). Its pages are `docs/app/views/pages/*.html.md`. Try overlay changes there in a
  browser before calling them done. `parcela up --detach` serves it at
    https://tensaku.localhost. `RAILS_ENV=production bin/rails kiln:build` in `docs/` must succeed.
- Run `bin/lint` and `bin/test` for code changes.
- Never run `gem push`, create the GitHub repo, push, or tag without the user's approval.
- No AI attribution in commits, pull requests or files.

Writing (README, CHANGELOG, comments): plain, factual sentences. Say what a thing does. No em dashes
outside the planning documents. Describe verified behavior only, and name what is unsupported.
