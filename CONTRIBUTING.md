# Contribute to Tensaku

Read [PLAN.md](PLAN.md) before a design change. Its decisions log records what Tensaku does and what it leaves out. [AGENTS.md](AGENTS.md) lists the project rules. Use jj for version control.

## Build and check code

```sh
bundle install
bun install
bunx playwright install chromium webkit
bin/lint
bin/test
```

`bin/lint` runs RuboCop, the house rules and the TypeScript check, and fails if the compiled overlay is out of date. `bin/test` runs the unit tests and the browser tests. The browser tests use Capybara on Playwright, as our other apps do. Install the browsers once with `bunx playwright install chromium webkit`. They run in Chromium; `SYSTEM_TEST_BROWSER=webkit bin/test` runs them in WebKit, Safari's engine, and `SYSTEM_TEST_HEADED=1` shows the browser. CI runs both.

The tests run `test/dummy` in the development environment, because Tensaku switches on only there. Browser tests write to the dummy app's files and restore them afterwards. `test/tensaku/production_test.rb` checks that test and production never load Tensaku, Herb or ReActionView.

## Change the overlay

The overlay source is `app/javascript/tensaku/*.ts`. Build it and commit the result:

```sh
bun run build
```

The build writes `app/assets/tensaku.js`, the script the middleware injects.

## Change how files are written

Every write is a byte splice with a stale check. Never load and dump YAML, and never re-serialize a template. Each new splice needs a test that the rest of the file is unchanged.

## Work on the documentation site

`docs/` is a separate Rails app with its own Gemfile. Kiln renders it to static files, and lostcoords-ui styles it. The pages are `docs/app/views/pages/*.html.md`. Tensaku runs on the site in development, so you can edit the docs from the page and try overlay changes on a real site.

```sh
cd docs
bundle install
bin/rails tailwindcss:build
bin/rails server
```

With [Parcela](https://parcela.run), `parcela up --detach` runs the server and the Tailwind watcher at https://tensaku.localhost.

Build the static site before you finish. CI runs the same build on every push.

```sh
RAILS_ENV=production bin/rails kiln:build
```

The landing page demo runs the built overlay against `docs/app/javascript/demo/server.js`, which stands in for the endpoints and plays back `demo/data.js`. After you change `docs/app/views/pages/landing.html.erb` or an endpoint's reply, run this in `docs/` and update `server.js` to match:

```sh
bin/rails runner script/demo_data.rb
```

## Releases

Only the maintainer publishes the gem, creates tags, or pushes.
