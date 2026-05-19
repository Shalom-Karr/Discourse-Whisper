# Documentation — discourse-whisper

Welcome to the documentation for the **discourse-whisper** Discourse plugin.

## Table of contents

### Getting started

- [Setup & Installation](setup.md) — how to install, enable, and configure the plugin
- [Feature list](features.md) — everything the plugin adds
- [Settings & features index](settings.md) — the site setting and a link to every feature

### Features

- [Whisper a post](whisper-a-post.md) — the toolbar eye button and the "Whisper to…" modal
- [Mention whisper hint](mention-whisper-hint.md) — arm a whisper straight from an `@mention`
- [Auto-whisper-back on reply](auto-whisper-back.md) — replies stay in the same private group
- [Whisper visibility](whisper-visibility.md) — who can read a whisper, and how it is enforced
- [`discourse_whisper_enabled`](discourse-whisper-enabled.md) — the master switch

### Reference

- [How Whispers Work](whispers.md) — the visibility rules, the composer UX, and auto-whisper-back in prose
- [Architecture](architecture.md) — the three enforcement hooks (Guardian, TopicView, Search), the shared SQL filter, and the composer integration
- [Tests & screenshots](testing.md) — the CI workflows, the Node helper tests, and a screenshot of every feature

## Quick overview

`discourse-whisper` adds a single post-level feature: a post can be marked as a **whisper to one or more specific users**. Non-recipients never see the post — it is hidden from the topic stream at the `Guardian#can_see_post?` layer, not redacted at the serializer layer, so the post body is never sent over the wire to anyone outside the audience.

The audience is:

- the **author**
- the **target users**
- **category group moderators** of that category
- **staff** (site-wide admins and moderators)

Moderators are an *oversight* audience, not an intended reader — they can review or flag whispers but the feature is designed around user-to-user communication.
