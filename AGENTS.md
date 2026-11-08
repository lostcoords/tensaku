# Tensaku

Tensaku edits text on a running Rails page in development and writes it back to the source, and keeps
notes for coding agents. Use jj for version control; never use mutating Git commands.

[CONTRIBUTING.md](CONTRIBUTING.md) has the build, test and docs commands. The rules:

- Read PLAN.md before design changes. Its decisions log is the reference for what Tensaku does and
  leaves out. ART_STYLE.md is the direction for the visual design pass.
- Nothing may change outside development: no loading Herb, ReActionView or Tensaku code in test or
  production (`test/tensaku/production_test.rb` checks it). New code goes behind the railtie's
  development check or Tensaku's autoloads.
- Writes are byte splices with a stale check. Never load and dump YAML, never re-serialize a template.
  Every new splice needs a test that the rest of the file is unchanged.
- After changing `app/javascript/tensaku/*.ts`, run `bun run build` and commit `app/assets/tensaku.js`.
- Try overlay changes on the docs site in a browser before calling them done. `RAILS_ENV=production
  bin/rails kiln:build` in `docs/` must succeed, and `script/demo_data.rb` must be rerun after changing
  the landing page or an endpoint's reply.
- Run `bin/lint` and `bin/test` for code changes.
- Never run `gem push`, push, or tag without the user's approval.
- No AI attribution in commits, pull requests or files.

Writing (README, CHANGELOG, comments): plain, factual sentences. Say what a thing does. No em dashes
outside the planning documents. Describe verified behavior only, and name what is unsupported.
