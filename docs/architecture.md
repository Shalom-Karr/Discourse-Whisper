# Architecture

The plugin is intentionally tiny — three load-bearing pieces, glued together by Discourse's plugin API.

## 1. The post custom field (`plugin.rb`)

A whisper post is just a regular post with a JSON custom field `whisper_target_user_ids` holding the array of recipient user IDs. `plugin.rb`:

- registers the field as a JSON-typed post custom field
- permits `whisper_target_user_ids` on post creation via `add_permitted_post_create_param`
- on `:post_created`, filters the incoming IDs down to those that resolve to real `User` records (rejects bogus IDs, coerces strings to ints, defensively drops hashes/symbols), deduplicates, caps at `DiscourseWhisper::MAX_WHISPER_TARGETS` (10), and writes the custom field
- adds three serializer fields on `Post`: `is_whisper_to_user` (boolean), `whisper_target_user_ids` (array of ints), and `whisper_targets` (array of `{id, username, avatar_template}`)

All serializer additions are gated on `SiteSetting.discourse_whisper_enabled` so the plugin can be hard-disabled without side effects.

## 2. Enforcement — three hooks, one shared filter

`Guardian#can_see_post?` is the per-post check — used by the direct post-show controller, raw/cooked endpoints, notification rendering, bookmark/like permission, revision history, etc. It's a single override in `lib/discourse_whisper/guardian_extensions.rb`:

- returns `false` unless the viewer is the author, in `whisper_target_user_ids`, site staff, or a category group moderator on the post's category
- anonymous viewers always see `false`
- **staff-to-staff exception**: when every participant (author + every target) is site staff, category group moderators are excluded — they have no oversight over staff-only conversations. Site admins and moderators still see everything.
- graceful degradation: blank targets, non-Post argument, plugin disabled, or malformed IDs all fall through to `super`

But `can_see_post?` alone does NOT filter bulk post-loading paths (topic stream, search, user-activity queries). Those are SQL-level queries that never iterate `can_see_post?` per row. So the plugin ships a shared SQL filter:

**`lib/discourse_whisper/query_filter.rb`** — `DiscourseWhisper::QueryFilter.apply(scope, user)` takes any AR `Post` scope and appends a `LEFT JOIN post_custom_fields` + `WHERE` clause that drops whispers the user can't see. Uses Postgres JSONB containment (`value::jsonb @> :user_id_json::jsonb`) for the target-list check and a correlated `EXISTS` on `category_moderation_groups` for the cat-mod override (with the staff-to-staff exception mirrored in SQL via `jsonb_array_elements_text` + `users.admin`/`users.moderator`).

The filter is wired into two places:

- **`TopicView.apply_custom_default_scope`** — applied to `@filtered_posts`, so the topic stream (and therefore `/t/:id.json`, the client post stream, paginated replies, etc.) is filtered
- **`Search.prepend(DiscourseWhisper::SearchExtension)`** — wraps `posts_query` so search results are filtered

All three (`Guardian`, `TopicView` hook, `Search` prepend) short-circuit when `SiteSetting.discourse_whisper_enabled` is false. The Guardian and Search modules are prepended via `reloadable_patch { ... }` so dev-mode code reloads pick them up.

## 3. The composer integration (`assets/javascripts/discourse/`)

Three entry points feed the same composer model field (`whisperTargetUserIds`):

- **Toolbar button + modal** — `initializers/discourse-whisper.js` registers the `far-eye` toolbar button; `components/whisper-target-modal.gjs` is the picker. The modal uses `EmailGroupUserChooser` capped at 10 users, resolves usernames → user objects via `/u/:username.json`, and writes `whisperTargetUserIds` / `whisperTargetUsernames` / `whisperTargets` onto the composer model.
- **Mention hint** — `connectors/composer-fields/whisper-mention-hint.gjs` watches `composer.reply` for `@username` tokens and renders a "Whisper to @user" pill below the composer when a mention isn't already in the audience. Same resolve-and-set path as the modal.
- **Reply auto-arm** — on `composer:opened` for a reply to a whisper, the initializer auto-arms a return whisper to (original author + other recipients − current user). The user can toggle it off via the armed-pill's close button.

The IDs are sent to the server via `api.serializeOnCreate("whisper_target_user_ids", "whisperTargetUserIds")`, which puts them on the post-create POST body where the `:post_created` handler picks them up.

The same initializer also:

- adds `is_whisper_to_user` / `whisper_target_user_ids` / `whisper_targets` to the post attributes the client deserializes
- decorates whisper posts in the stream with a `.whisper-to-user` class on `<article>` and a `.whisper-target-banner` showing recipients

A fourth connector, `connectors/composer-fields/whisper-armed-pill.gjs`, renders a "Whispering to @user1, @user2 [×]" pill inside `.composer-fields` whenever a whisper is armed. Its DOM presence is what triggers the indigo composer tint via SCSS `:has()` — the tint and the pill are one signal, not two.

## Webhook dispatch

`WebHook.enqueue_post_hooks` is the single entry point Discourse uses to queue webhook jobs for post events (`post_created`, `post_edited`, `post_destroyed`, `post_recovered`). The plugin prepends `DiscourseWhisper::WebHookExtension` onto `WebHook.singleton_class` to drop the enqueue for any post with a `whisper_target_user_ids` custom field. Whisper content is never sent to an admin-configured webhook URL.

## Why everything keys off one custom field

Because the audience is just a JSON array on the post, the plugin needs no migrations, no extra tables, no background jobs, and no API endpoints. Adding recipients at post-create time is a single filter-and-save. Deleting a whisper is just deleting the post. The visibility check runs on every `can_see_post?` call, but it's a hash lookup on already-loaded custom fields — cheap. Bulk queries pay one extra LEFT JOIN.

## Settings

One site setting: `discourse_whisper_enabled` (default `true`). When false, every hook (Guardian, TopicView scope, Search prepend, serializer additions, post-create event handler) short-circuits. The plugin becomes fully inert without a server restart.

In specs that touch category-group moderation, the relevant setting is `enable_category_group_moderation` — set it in the spec `before` block when the test depends on a category moderator seeing the whisper.

## Conventions

- Ruby files use `# frozen_string_literal: true` at the top
- Specs use Discourse's `fab!` fabricator helper (memoized fabrication) and `require "rails_helper"`
- Request specs have `type: :request` metadata so `sign_in`/`get`/`response` resolve via Discourse's `IntegrationHelpers`
- The plugin targets `required_version: 2.7.0` (Discourse), Ruby 3.4, Node 22
- Composer-side state of truth is the trio `whisperTargetUserIds` / `whisperTargetUsernames` / `whisperTargets` — keep them in sync when adding new entry points
