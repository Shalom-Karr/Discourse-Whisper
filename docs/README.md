# Documentation — discourse-whisper

Welcome to the documentation for the **discourse-whisper** Discourse plugin.

## Table of contents

- [Setup & Installation](setup.md) — how to install, enable, and configure the plugin
- [How Whispers Work](whispers.md) — the visibility rules, the composer UX, and auto-whisper-back on reply
- [Architecture](architecture.md) — the three enforcement hooks (Guardian, TopicView, Search), the shared SQL filter, and the composer integration
- [Running the Test Suite](testing.md) — the GitHub Actions CI workflow, the Docker local loop, and the Node helper tests

## Quick overview

`discourse-whisper` adds a single post-level feature: a post can be marked as a **whisper to one specific user**. Non-recipients never see the post — it is hidden from the topic stream at the `Guardian#can_see_post?` layer, not redacted at the serializer layer, so the post body is never sent over the wire to anyone outside the audience.

The audience is:

- the **author**
- the **target user**
- **category group moderators** of that category
- **staff** (site-wide admins and moderators)

Moderators are an *oversight* audience, not an intended reader — they can review or flag whispers but the feature is designed around user-to-user communication.
