# How Whispers Work

## The composer UX

The composer toolbar gains a small 👁 **eye** button in the `extras` group — the same visual language Discourse already uses for native staff whispers, but pointed at a hand-picked audience instead of all staff. Clicking it opens a tiny modal titled **"Whisper to…"** with a multi-user picker (a `EmailGroupUserChooser` restricted to users, no groups, with `maximum: 10`).

Once one or more targets are picked:

- the target ids are stored on the composer model as `whisperTargetUserIds` (array of ints)
- the composer gains a pale indigo tint so the author can't forget it's a whisper
- on submit, the ids are serialized onto the post create request as `whisper_target_user_ids[]` via `api.serializeOnCreate`

If the author reopens the modal, the current selection is preselected and a **Clear** button reverts the composer to a normal post.

### Mention-integrated shortcut

The toolbar modal is the canonical way to arm a whisper, but the plugin also watches the composer body for `@mentions` as the author types. When one or more mentions appear that are *not* already in the whisper audience, a small pill button slides in below the composer that reads **"Whisper to @user, @user2"** (or **"Also whisper to @user3"** if a whisper is already armed). Clicking it resolves those usernames to ids and adds them to `whisperTargetUserIds` — same server path as the modal, no extra backend code.

This is the "tag someone and you're offered a whisper" flow. It's sleek (invisible until mentions exist) and obvious (appears right under the composer where the author is looking). The author can still ignore the hint and post publicly, or use the toolbar eye button for the full picker UI.

The connector lives at [`assets/javascripts/discourse/connectors/composer-fields/whisper-mention-hint.gjs`](../assets/javascripts/discourse/connectors/composer-fields/whisper-mention-hint.gjs). It tracks `composer.reply` reactively, so the hint appears and updates as the user types.

## How the post is saved

The server side is deliberately minimal:

1. `plugin.rb` registers a JSON post custom field type: `register_post_custom_field_type("whisper_target_user_ids", :json)`
2. It permits the parameter on post create: `add_permitted_post_create_param(:whisper_target_user_ids, :array)`
3. It listens to the `:post_created` Discourse event, filters the ids down to those that resolve to real users, and writes `post.custom_fields["whisper_target_user_ids"]`
4. The custom field is surfaced on the post serializer as `is_whisper_to_user`, `whisper_target_user_ids`, and a richer `whisper_targets` array (`[{id, username, avatar_template}, ...]`) — gated on `SiteSetting.discourse_whisper_enabled` and on the custom field being present

## The visibility rule

Per-post access lives in a single `Guardian#can_see_post?` override in `lib/discourse_whisper/guardian_extensions.rb`. Bulk-load paths (topic stream, search, user-activity queries) are filtered at the SQL level by `DiscourseWhisper::QueryFilter` — see [`architecture.md`](architecture.md) for the three-hook layout.

The Guardian rule in plain terms:

1. If the plugin is disabled, fall through to core.
2. If the post has no `whisper_target_user_ids` custom field, fall through to core.
3. Anonymous viewers: always hidden.
4. Author of the post: always visible.
5. Viewer is in the target list: always visible.
6. Viewer is site staff (admin or moderator): always visible (oversight).
7. Viewer is a category group moderator on the post's category: visible, **unless** the whisper is staff-to-staff (author AND every target is site staff). Staff-only conversations are excluded from cat-mod oversight.
8. Everyone else: hidden.

`false` at the Guardian layer means Discourse drops the post from the topic stream entirely — non-recipients don't see a placeholder, a stub, or a gap-explanation. The post's `cooked` content is never included in the serialized response they receive.

## The visibility matrix

| Viewer | Mixed-audience whisper | Staff-to-staff whisper |
|---|---|---|
| Author | ✅ | ✅ |
| Any target recipient | ✅ | ✅ |
| Admin | ✅ (oversight) | ✅ (oversight) |
| Moderator | ✅ (oversight) | ✅ (oversight) |
| Category group moderator on that category | ✅ (oversight) | ❌ (no staff-on-staff oversight) |
| Regular user not in the target list | ❌ | ❌ |
| Anonymous viewer | ❌ | ❌ |

"Staff-to-staff" = the author is admin-or-moderator **and** every entry in `whisper_target_user_ids` resolves to an admin-or-moderator user.

## Rendering on the recipient side

On posts that *are* visible, the client-side `decorateCookedElement` decorator:

- adds a `.whisper-to-user` class to the post `<article>`, giving it a pale indigo left border
- injects a `<div class="whisper-target-banner">` with the 👁 icon, the text `whisper to`, and a comma-separated list of `@username` profile links — one for each recipient

This is the only visual indication — the post otherwise looks like any other post in the stream.

## Auto-whisper-back on reply

Replies to a whisper are pre-armed as whispers back to the rest of the original audience. The initializer listens for `composer:opened` and, if the post being replied to has `is_whisper_to_user` set, it builds the reply audience as:

> the original **author** plus every **target** from `whisper_targets`, minus the **current user** themself

So the conversation stays in the same small group, and nobody new is pulled in by default:

- If the current user is the **author**, the reply targets everyone originally whispered to
- If the current user is **one of the targets**, the reply targets the author plus the other recipients
- The current user is always removed from the audience (they don't whisper to themselves)

The toolbar eye button still works and can toggle the audience off (or open the modal and adjust it), so the user can always publish a public reply if they want.

## Why hidden rather than a placeholder?

Our first design draft sent a collapsed `👁 whisper to @username` row to non-recipients. We pivoted to fully hiding the post because:

1. **Privacy**: with a placeholder, non-recipients learn *that* a private exchange is happening and *who* it is directed at. That's itself a disclosure — if Alice whispers to Bob in public view, everyone now knows Alice had a private thing to say to Bob, which may be the thing she was trying to avoid in the first place. With a multi-user audience this leaks even more (the whole recipient list).
2. **Simplicity**: enforcing visibility at `Guardian#can_see_post?` is a single well-understood extension point. Redacting `cooked` server-side while keeping the post in the stream requires overriding `PostSerializer#cooked` and reasoning about every other place that reads post content.
3. **Mod oversight is not harmed**: category group moderators and staff still see the whisper in the stream with the banner, so the flag path is unchanged.
