# discourse-whisper

> A private aside, just for the people you pick — with mod oversight built in.

A Discourse plugin that lets any post be sent as a **whisper to one or more target users**. The post is hidden from everyone on the site *except* the author, the chosen recipients, category moderators, and staff. Moderators can still see the whisper so they can review or flag it if it's inappropriate.

Architecturally inspired by [discourse-mini-mod](https://github.com/alltechdev/discourse-mini-mod) and [discourse-admin-messenger](https://github.com/Shalom-Karr/Discourse-Messaging-Plugin-YOLO).

## How it works

1. **Author clicks the 👁 eye button** in the composer toolbar — or just types `@username` in the post body and clicks the **"Whisper to @username"** hint that appears below the composer
2. A tiny modal opens (when using the toolbar button) and they pick **one or more users** as whisper targets (up to 10 per post)
3. They write and post as normal — the composer picks up a pale indigo tint so they can't forget it's a whisper
4. The post is saved with a `whisper_target_user_ids` JSON custom field
5. When the topic is rendered, `Guardian#can_see_post?` returns `false` for anyone who isn't:
   - the author
   - any of the target users
   - a member of a category group moderator group on that category
   - staff (admin / moderator)
6. Non-recipients see nothing — the post is absent from the stream entirely
7. Recipients see a pale 👁 `whisper to @user1, @user2` banner above the post body, and a soft indigo left border on the post itself
8. When a recipient replies to a whisper, the composer **auto-arms** a whisper back to everyone else in the original audience (author + other recipients), minus the current user. The eye toggle in the toolbar can be clicked to disable it.

## Visibility matrix

| Viewer | Sees the whisper? |
|---|---|
| Author | ✅ Yes |
| Any target user | ✅ Yes |
| Admin | ✅ Yes (oversight) |
| Moderator | ✅ Yes (oversight) |
| Category group moderator (on that category) | ✅ Yes (oversight) |
| Anyone else (incl. anonymous) | ❌ No — fully hidden |

## Settings

All settings are under **Admin → Site Settings → Discourse Whisper**.

| Setting | Default | Description |
|---|---|---|
| `discourse_whisper_enabled` | `true` | Master switch for the plugin |

## Installation

Add the plugin to your container's `app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/Shalom-Karr/Discourse-Whisper.git discourse-whisper
```

Then rebuild:

```
./launcher rebuild app
```

## Documentation

See [`docs/`](docs/) for detailed documentation:

- [Setup & Installation](docs/setup.md)
- [How Whispers Work](docs/whispers.md)
- [Running the Test Suite](docs/testing.md) — using GitHub Actions
