# Running the Test Suite

This plugin uses **GitHub Actions** to run its RSpec specs against the main branch of `discourse/discourse`. The workflow is defined in [`.github/workflows/plugin-tests.yml`](../.github/workflows/plugin-tests.yml).

The workflow is self-contained — no Docker image, no pre-baked environment, no local Discourse checkout required. It spins up a fresh Postgres + Redis on the runner, clones Discourse and this plugin side-by-side, installs gems and JS deps, migrates the test DB, and runs `rspec plugins/discourse-whisper/spec`.

## Triggering the suite

The workflow runs automatically on:

- **Push to `main`** — every commit on main runs the full suite
- **Pull request** — every PR runs the full suite against the PR head

You can also re-run it manually from the **Actions** tab → **Plugin Tests** → **Re-run jobs**.

## What the workflow does

Each job step in order:

### 1. Checkout Discourse

```yaml
- uses: actions/checkout@v4
  with:
    repository: discourse/discourse
    path: discourse
```

Clones `discourse/discourse` (main branch) into `./discourse` on the runner.

### 2. Checkout the plugin

```yaml
- uses: actions/checkout@v4
  with:
    path: discourse/plugins/discourse-whisper
```

Clones this repo directly into `discourse/plugins/discourse-whisper` — the path Discourse's test loader expects.

### 3. Set up Ruby 3.4

```yaml
- uses: ruby/setup-ruby@v1
  with:
    ruby-version: "3.4"
    bundler-cache: false
```

Installs the Ruby version Discourse targets.

### 4. System dependencies

```bash
sudo apt-get update -qq
sudo apt-get install -y libpq-dev libssl-dev imagemagick
```

These are the native libs Discourse's gems link against.

### 5. Redis

```bash
sudo apt-get install -y redis-server
sudo service redis-server start
redis-cli ping
```

A local Redis instance; Discourse's test suite uses it for caching and message bus.

### 6. Node + pnpm

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 22
- run: npm install -g pnpm
```

Node 22 with pnpm — required because Discourse's `db:migrate` depends on `assets:precompile:asset_processor`, which in turn reads the pnpm lockfile to compute a cache digest. Without pnpm installed, migrations abort.

### 7. JS dependencies

```bash
pnpm install
```

Run inside the `discourse/` directory. This resolves and installs Discourse's frontend packages — fast because Discourse's pnpm lockfile is pinned.

### 8. Bundle install

```bash
bundle install --jobs 4 --retry 3
```

Installs Discourse's gem bundle. This is the slowest step — typically 2–5 minutes on a cold runner.

### 9. Database setup

```bash
bundle exec rake db:create db:migrate
```

Creates and migrates the `discourse_test` Postgres database. `RAILS_ENV=test` and `LOAD_PLUGINS=1` are set at the job level so plugin migrations (if any) are included.

### 10. Run the plugin specs

```bash
bundle exec rspec plugins/discourse-whisper/spec \
  --format documentation
```

`LOAD_PLUGINS=1` is the critical bit — without it, `Guardian.prepend(DiscourseWhisper::GuardianExtensions)` in `after_initialize` never fires, and the guardian specs fail because the override isn't loaded.

## What gets tested

The specs live in [`spec/lib/`](../spec/lib/) and cover:

### `guardian_extensions_spec.rb`

The visibility rule for `Guardian#can_see_post?` on whisper posts. Cases:

- Plugin disabled → falls through to default Guardian behaviour
- Whisper post, viewer is the **author** → ✅ visible
- Whisper post, viewer is the **target user** → ✅ visible
- Whisper post, viewer is an **admin** → ✅ visible (oversight)
- Whisper post, viewer is a **moderator** → ✅ visible (oversight)
- Whisper post, viewer is a **category group moderator** → ✅ visible (oversight)
- Whisper post, viewer is an **unrelated user** → ❌ hidden
- Whisper post, viewer is **anonymous** → ❌ hidden
- Non-whisper post → falls through to defaults
- Malformed / zero target id → falls through to defaults (graceful degradation)

### `post_custom_fields_spec.rb`

The `on(:post_created)` event handler that writes the `whisper_target_user_id` custom field. Cases:

- Valid target id → custom field is saved
- Nonexistent target id → custom field is **not** saved (ignored)
- Zero / negative target id → ignored
- Plugin disabled → ignored even when a valid id is passed

## Reading the results

On the **Actions** tab of the GitHub repo, a green check on the **Plugin Tests** workflow means the full spec suite passed. If it fails, click into the run to see the `Run plugin specs` step — RSpec's `--format documentation` output lists every example with its describe-context hierarchy, so failures are easy to locate.

## Running the specs locally

If you want to reproduce the workflow on your own machine without Docker:

1. Clone `discourse/discourse` somewhere
2. Clone this plugin into `discourse/plugins/discourse-whisper`
3. Install Postgres 16 and Redis locally and ensure they're running
4. Install Ruby 3.4, Node 22, and pnpm
5. `cd discourse && bundle install && pnpm install`
6. `RAILS_ENV=test LOAD_PLUGINS=1 bundle exec rake db:create db:migrate`
7. `RAILS_ENV=test LOAD_PLUGINS=1 bundle exec rspec plugins/discourse-whisper/spec`

To run a single file:

```bash
RAILS_ENV=test LOAD_PLUGINS=1 bundle exec rspec \
  plugins/discourse-whisper/spec/lib/guardian_extensions_spec.rb
```

To run a single describe block:

```bash
RAILS_ENV=test LOAD_PLUGINS=1 bundle exec rspec \
  plugins/discourse-whisper/spec/lib/guardian_extensions_spec.rb \
  -e "#can_see_post?"
```

To run a single example by line number:

```bash
RAILS_ENV=test LOAD_PLUGINS=1 bundle exec rspec \
  plugins/discourse-whisper/spec/lib/guardian_extensions_spec.rb:42
```

## Why GitHub Actions instead of Docker?

The [upstream `discourse-mini-mod` testing guide](https://github.com/alltechdev/discourse-mini-mod/blob/master/docs/testing.md) uses `discourse/discourse_dev:release` as a pre-baked Docker image to skip the `bundle install` cost on every run. That works well for a developer running specs repeatedly on one machine, because the image is downloaded once and reused.

We went with GitHub Actions instead because:

1. **Zero local setup for contributors** — a PR from a stranger gets the full test run for free, no Docker install, no Discourse checkout, no image pull
2. **Pinned environment** — the runner image + the workflow steps are the same every time, so "works on my machine" is harder to hit
3. **Single source of truth** — the green check on a PR is authoritative, tied to a specific commit SHA, visible to reviewers
4. **Cost is still bounded** — the Discourse clone + `bundle install` is a few minutes on a cold runner, but the workflow only runs on push/PR, not on every local file save

The tradeoff: a cold CI run is slower than a warm local Docker run (no cached bundle). For rapid iteration, `rspec` inside `discourse/discourse_dev` is still the better local loop — see the [mini-mod guide](https://github.com/alltechdev/discourse-mini-mod/blob/master/docs/testing.md) for that flow.
