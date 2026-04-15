# How Whispers Work

## The composer UX

The composer toolbar gains a small 👁 **eye** button in the `extras` group — the same visual language Discourse already uses for native staff whispers, but pointed at a single user instead of all staff. Clicking it opens a tiny modal titled **"Whisper to…"** with a single-user picker (a `EmailGroupUserChooser` restricted to users, no groups).

Once a target is picked:

- the target user id is stored on the composer model as `whisperTargetUserId`
- the composer gains a pale indigo tint so the author can't forget it's a whisper
- on submit, the id is serialized onto the post create request as `whisper_target_user_id` via `api.serializeOnCreate`

If the author reopens the modal, the current target is preselected and a **Clear** button reverts the composer to a normal post.

## How the post is saved

The server side is deliberately minimal:

1. `plugin.rb` registers a post custom field type: `register_post_custom_field_type("whisper_target_user_id", :integer)`
2. It permits the parameter on post create: `add_permitted_post_create_param(:whisper_target_user_id)`
3. It listens to the `:post_created` Discourse event, validates the id points at a real user, and writes `post.custom_fields["whisper_target_user_id"]`
4. The custom field is surfaced on the post serializer as `is_whisper_to_user`, `whisper_target_user_id`, `whisper_target_username`, and `whisper_target_avatar_template` — gated on `SiteSetting.discourse_whisper_enabled` and on the custom field being present

## The visibility rule

All access enforcement lives in a single `Guardian#can_see_post?` override in `lib/discourse_whisper/guardian_extensions.rb`:

```ruby
def can_see_post?(post)
  return super unless SiteSetting.discourse_whisper_enabled
  return super unless post.is_a?(::Post)

  raw_target = post.custom_fields["whisper_target_user_id"]
  return super if raw_target.blank?

  target_id = raw_target.to_i
  return super if target_id <= 0

  return super if @user && post.user_id == @user.id          # author
  return super if @user && @user.id == target_id             # target
  return super if @user&.staff?                              # site staff
  category = post.topic&.category
  return super if category && @user && is_category_group_moderator?(category)

  false                                                      # everyone else
end
```

`false` at the Guardian layer means Discourse drops the post from the topic stream entirely — non-recipients don't see a placeholder, a stub, or a gap-explanation. The post's `cooked` content is never included in the serialized response they receive.

## The visibility matrix

| Viewer | Sees the whisper? | Why |
|---|---|---|
| Author | ✅ | `post.user_id == current_user.id` |
| Target user | ✅ | `current_user.id == whisper_target_user_id` |
| Admin | ✅ | `current_user.staff?` (oversight) |
| Moderator | ✅ | `current_user.staff?` (oversight) |
| Category group moderator on that category | ✅ | `Guardian#is_category_group_moderator?` (oversight) |
| Regular user | ❌ | falls through to `false` — post never reaches their serializer |
| Anonymous viewer | ❌ | same |

## Rendering on the recipient side

On posts that *are* visible, the client-side `decorateCookedElement` decorator:

- adds a `.whisper-to-user` class to the post `<article>`, giving it a pale indigo left border
- injects a `<div class="whisper-target-banner">` with the 👁 icon, the text `whisper to`, and an `@username` link to the target's profile

This is the only visual indication — the post otherwise looks like any other post in the stream.

## Auto-whisper-back on reply

Replies to a whisper are pre-armed as whispers back to the other side of the conversation. The initializer listens for `composer:opened` and, if the post being replied to has `is_whisper_to_user` set and the current user is one of the two participants, sets the composer's `whisperTargetUserId` to the *other* participant:

- If the current user is the **author**, reply targets the original whisper's target user
- If the current user is the **target user**, reply targets the original whisper's author

The toolbar eye button still works and can toggle the target off, so the user can always publish a public reply if they want.

## Why hidden rather than a placeholder?

Our first design draft sent a collapsed `👁 whisper to @username` row to non-recipients. We pivoted to fully hiding the post because:

1. **Privacy**: with a placeholder, non-recipients learn *that* a private exchange is happening and *who* it is directed at. That's itself a disclosure — if Alice whispers to Bob in public view, everyone now knows Alice had a private thing to say to Bob, which may be the thing she was trying to avoid in the first place.
2. **Simplicity**: enforcing visibility at `Guardian#can_see_post?` is a single well-understood extension point. Redacting `cooked` server-side while keeping the post in the stream requires overriding `PostSerializer#cooked` and reasoning about every other place that reads post content.
3. **Mod oversight is not harmed**: category group moderators and staff still see the whisper in the stream with the banner, so the flag path is unchanged.
