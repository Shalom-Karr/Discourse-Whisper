# Settings & features reference

The site setting below lives under **Discourse Whisper** at `/admin/site_settings/category/discourse_whisper`. It is the plugin's single master switch — all whisper behaviour (the composer UI and the visibility enforcement) is gated on it.

## Site settings

| Setting | Default | Documentation |
|---|---|---|
| `discourse_whisper_enabled` | `true` | [Master switch](discourse-whisper-enabled.md) |

## Features (no separate site setting)

Every feature below is active whenever `discourse_whisper_enabled` is on; none has its own toggle.

| Feature | Documentation |
|---|---|
| Whisper a post to chosen users | [Whisper a post](whisper-a-post.md) |
| Mention-integrated whisper hint | [Mention whisper hint](mention-whisper-hint.md) |
| Auto-whisper-back on reply | [Auto-whisper-back on reply](auto-whisper-back.md) |
| Whisper visibility & moderator oversight | [Whisper visibility](whisper-visibility.md) |

## Who can do what

Any user who can post may **create** a whisper. Who can **read** one is enforced by `Guardian#can_see_post?` and the shared SQL filter: the author, the target users, category group moderators, and site staff. See [Whisper visibility](whisper-visibility.md) for the full matrix.

## Tests & screenshots

See [Tests & screenshots](testing.md) for the test-suite overview and a screenshot of every feature.
