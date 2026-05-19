---
name: tests_ran
description: Complete inventory of the plugin's test suite — rspec, Node helper tests, and QUnit — with the most recent local run result
type: doc
---

# Tests Ran

## Local run (2026-04-16, Docker `discourse/discourse_dev:release`)

- **RSpec: 237 examples, 0 failures** (~22s)
- **Node helper tests: 99 tests, 0 failures** (~60ms)
- **Total: 336 tests — 0 failures**

Both suites are run in CI on every push/PR and block merge.

### Real bugs found and fixed before green

The first full run produced **12 failures** that exposed real plugin defects:

1. `TopicView` did not filter whispers — strangers saw them in the topic stream and `/t/:id.json`. Fixed by wiring `TopicView.apply_custom_default_scope` to a shared `DiscourseWhisper::QueryFilter`.
2. `Search` did not filter whispers — search results leaked whisper content to strangers. Fixed by prepending `DiscourseWhisper::SearchExtension` onto `Search#posts_query`.
3. `Post.where(user_id: author.id)` (user-activity style queries) did not filter — covered by the same shared `QueryFilter`.
4. Post-create handler crashed with `NoMethodError` on hash/symbol inputs — added defensive `Numeric||String` coercion.

The tests that now pass green lock these fixes in.

### Verified-safe leak vectors (positive regression locks)

The notification-leak spec probes and pins down behavior at the boundaries:

- **Stranger @-mentioned in a whisper body** → 0 notifications created. Discourse's `PostAlerter` checks `Guardian#can_see_post?`, so our override feeds it correctly. Baseline test confirms the plumbing actually works for normal posts.
- **Group @-mention in a whisper** → outsiders don't get notified; group members who are ALSO whisper targets DO.

### Webhook dispatch is patched

- **Webhook payloads**: `WebHook.enqueue_post_hooks` is prepended via `DiscourseWhisper::WebHookExtension` to drop webhook events for any post with a whisper custom field. Covered by `spec/integration/webhook_leak_spec.rb` — verifies all four post-event types (`post_created`, `post_edited`, `post_destroyed`, `post_recovered`) are blocked, normal posts still fire, topic-level hooks still fire, and the block lifts when the plugin is disabled.

Run locally with:

```bash
# RSpec
docker exec -u discourse:discourse -w /src \
  -e RAILS_ENV=test -e LOAD_PLUGINS=1 \
  discourse_dev bin/rspec plugins/discourse-whisper/spec

# Node JS helper tests (host)
cd ~/Discourse-Whisper && node --test test/node/run-helper-tests.mjs
```

## RSpec coverage

### `spec/lib/guardian_extensions_spec.rb` — `Guardian#can_see_post?`

- Plugin disabled: stranger / anon / author all fall through to core
- Single-target whisper: author / target / admin / moderator can see; stranger / anon cannot
- Multi-target whisper: every target, the author see; a third party and strangers cannot
- Author also listed as a target: everyone who should still sees, others still hidden
- Target ids stored as JSON strings → still resolves
- Target ids stored as a mix of valid, zero, negative, "abc", bogus large → valid ones still work
- Only-invalid ids stored → falls through to super
- Non-Post arg (nil, string) → does not add a plugin-level raise on top of core
- Category group moderator of the post's category → can see
- Category group moderator of a *different* category → cannot see
- Category group moderation feature disabled site-wide → cat mod cannot see
- Topic with no category (PM) → does not raise; target still sees (with PM access)
- Normal posts: stranger and author both see as usual
- Malformed / zero / negative / empty / nil field → falls through to super
- Stored scalar integer, scalar string, floats → all coerced correctly
- Large (20+) stored target list
- Soft-deleted whisper post → admin still sees, stranger does not, no raise
- Soft-deleted topic containing the whisper → does not raise
- System user as author → visibility still enforced
- Bot user (user_id < 0) as author → visibility still enforced
- Hard-deleted target leaves the live target still visible
- Inactive target can still see the whisper
- Suspended target can still see the whisper

### `spec/lib/post_custom_fields_spec.rb` — `:post_created` event handler

- Single / multiple target ids on create
- Mix of valid + bogus ids → bogus dropped
- All bogus → field not saved
- Plugin disabled → field not saved
- Zero / negative ids ignored
- Duplicate ids deduplicated
- String ids coerced to ints
- Mix of valid, zero, negative, "abc", "42abc", bogus string ids
- `nil`, missing, or empty array input
- Single (non-array) scalar id
- Float ids truncated
- nil entries in array ignored
- Author self-targeting accepted
- Suspended users accepted as targets
- Post edit is a no-op for the whisper audience (no `:post_edited` listener)
- Persistence survives a `Post.find` reload
- Large audience (8+) stored without truncation
- Whisper can be created inside a PM topic when the target is a PM participant
- Custom field is re-serialized correctly through PostSerializer after reload
- Author-only self-targeting accepted
- Hash / symbol / nested-array inputs are dropped without raising (defensive coercion)

### `spec/serializers/post_serializer_spec.rb` — `PostSerializer` additions

- `is_whisper_to_user`: true for whisper posts, false for normal, omitted when plugin disabled
- `whisper_target_user_ids`: integer array, single-target case, omitted for normal / disabled; coerces stored strings
- `whisper_targets`: returns `{id, username, avatar_template}` per recipient; silently drops deleted users; ID list keeps deleted user's id; empty-array shape when all deleted; omitted for normal / disabled; consistent for target / admin viewers; handles 25+ recipients

### `spec/integration/topic_view_spec.rb` — topic stream filtering

- Stranger does not see whisper posts in the stream
- Stranger still sees every non-whisper post
- Anon viewer does not see whispers
- Author / target / admin / moderator all see whispers
- Secondary target sees only the multi-target whisper, not the single
- Category group moderator of the topic's category sees whispers
- Category group moderator does NOT see whispers in categories they don't moderate
- Plugin disabled → stranger sees every post
- Stranger's filtered post count is strictly less than author's total

### `spec/integration/search_spec.rb` — search result filtering

- Whisper does not surface for a stranger
- Whisper does not surface for an anon viewer
- Whisper surfaces for the target / author / admin
- Plugin disabled → whisper surfaces for strangers (no enforcement)

### `spec/integration/user_activity_spec.rb` — `DiscourseWhisper::QueryFilter`

- Stranger / anon: whispers filtered out of `Post.where(user_id:)`
- Target / secondary target / author / admin / moderator: whispers visible
- Category group mod: visible for their category, not for others
- Plugin disabled: no filtering
- Non-whisper posts are never filtered

**SQL filter robustness:**

- Idempotent when applied twice
- Preserves existing `.where`, `.order`, `.limit` on the input scope
- Works on an empty scope
- Handles corrupt stored values (hash/object, empty string, literal `"null"`, empty array `"[]"`) without raising

### `spec/integration/category_interaction_spec.rb` — interplay with secured categories

- A target who cannot see the secured category cannot see whispers in it (core category-access precedence)
- Admins still see whispers in secured categories
- Strangers still hidden
- Documents that `QueryFilter` is one layer — upstream category security still applies

### `spec/integration/reactions_bookmarks_spec.rb` — interaction surface

- Strangers cannot bookmark / like a post they can't see (gated via `Guardian#can_see_post?`)
- Targets can bookmark and like the whisper
- Authors can bookmark

### `spec/integration/notification_leak_spec.rb` — mention notifications

- A stranger @-mentioned inside a whisper cannot render the post the notification would point at (`Guardian#can_see_post?` is false)
- A recipient of a whisper can render the post they'd be notified about

### `spec/integration/post_api_spec.rb` — API endpoints

- `GET /posts/:id.json`: denied for stranger / anon, allowed for author / target / admin; metadata (`is_whisper_to_user`, `whisper_target_user_ids`, `whisper_targets`) present for authorized viewers
- `GET /t/:slug/:id.json`: stream excludes whisper for stranger, includes for target / admin
- `GET /raw/:topic_id/:post_number`: denied for stranger / anon, allowed for author / target
- `GET /posts/:id/cooked.json`: denied for stranger, allowed for target

### `spec/integration/post_revisions_spec.rb` — revision history

- `GET /posts/:post_id/revisions/:revision.json`: denied for stranger / anon, allowed for admin

## Node helper tests (99 tests)

Located at `test/node/run-helper-tests.mjs`. Exercises the pure-JS helpers `extractMentionedUsernames`, `pendingMentions`, and `computeReplyAudience` without a browser.

### `extractMentionedUsernames` (59 tests)

- Empty / null / undefined / number / object inputs
- No `@` fast path
- Mention at start / after space / newline / tab / carriage return / opening paren / nested parens
- Does NOT match emails (standalone, embedded, adjacent to a real mention)
- Multiple mentions (across spaces and lines)
- Dedup exact and case-insensitive, preserves first casing
- Usernames with dot / underscore / dash / digits / only-digits
- Exactly 60 chars accepted; 61 chars capped at 60
- Bare `@`, `@ `, `@!`, `@%` rejected
- Non-ASCII (`@你好`) and emoji (`@🍕`) rejected
- Stops at space / comma; greedy-consumes trailing dot (documented)
- `@@alice`, `hi @@alice`, `foo@alice` mid-word not matched
- URL-path `site.com/@alice`, backtick `` `@alice` ``, `>@alice` without space not matched
- `> @alice` (markdown quote) IS matched
- Stops at `!`, `?`, `:`
- `\n@alice` at start matched
- `MENTION_RE.global` flag present; state resets between calls
- 50 mentions at once
- Mixed scripts: `@alice你好` matches only `alice`, `@alice🍕` stops at emoji
- Non-breaking space (`\u00A0`), vertical tab (`\v`), form feed (`\f`) all valid prefixes (JS `\s`)
- `[@alice]`, `{@alice}`, `"@alice"`, `'@alice'` not matched (no bracket/quote in prefix set)
- `# @alice` (markdown heading with space) matched
- Single-char usernames: `@-`, `@_`, `@.` all accepted
- 100-repeat mention deduplicates to one

### `pendingMentions` (10 tests)

- Nothing mentioned / all armed / partial overlap
- Case-insensitive armed matching
- null / undefined / empty armed lists
- Skips non-string armed entries
- Empty / null reply

### `computeReplyAudience` (24 tests)

- null / undefined post → []
- null / undefined / 0 currentUserId → []
- Full audience (author + targets)
- Current user excluded (author / target cases)
- Dedup author-in-targets and duplicate targets
- Preserves id / username / avatar_template
- Missing / non-array whisper_targets
- Skips null / undefined / falsy-id target entries
- Ordering: author first, then targets in order
- Large target list (50)

## CI history

| Run | Commit | Result |
|---|---|---|
| [24472508462](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24472508462) | merge commit | ❌ failure (pre-multi-user, pre-Guardian fix) |
| [24473109201](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24473109201) | `3bafcd2` | ❌ failure — `AnonymousUser#id` undefined + `reviewable_by_group_id` removed |
| [24473431030](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24473431030) | `32cc9ae` | ✅ success — 21/21 |
| [24474262707](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24474262707) | `0dc2eaf` (Option B mention hint) | ✅ success — 21/21 |
| local | `HEAD` (this rewrite) | ✅ success — 237 rspec + 99 node = 336 / 0 failures |
