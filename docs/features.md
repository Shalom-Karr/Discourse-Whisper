# Features

`discourse-whisper` ("Whisper") is a Discourse plugin that lets any post be sent as a **private whisper to one or more hand-picked users**. The post is hidden from everyone on the site except the author, the chosen recipients, category moderators, and site staff. This page lists everything the plugin adds.

## Whisper a post to chosen users

From the composer toolbar, a 👁 **eye** button opens a modal where the author picks up to 10 users as the whisper audience. The post is then visible only to that audience (plus oversight roles). See [Whisper a post](whisper-a-post.md).

## Mention-integrated whisper hint

As the author types `@username` in the composer body, a pill button slides in below the composer reading **"Whisper to @username"**. Clicking it adds those mentioned users to the whisper audience — the same result as the toolbar modal, without opening it. See [Mention whisper hint](mention-whisper-hint.md).

## Auto-whisper-back on reply

When a recipient replies to a whisper, the composer pre-arms a whisper back to the rest of the original audience (the author plus the other recipients, minus the replier). The conversation stays in the same small group by default. See [Auto-whisper-back on reply](auto-whisper-back.md).

## Whisper visibility & moderator oversight

A whisper post is hidden at the `Guardian#can_see_post?` layer and filtered out of every bulk-load path (topic stream, search, posts API, user activity, webhooks). The audience is the author, the target users, category group moderators, and site staff. A **staff-to-staff** whisper (staff author, all-staff targets) additionally excludes category group moderators. See [Whisper visibility](whisper-visibility.md).

## Permissions

Any user who can post may mark a post as a whisper — there is no extra trust level or group gate. The visibility rules govern who can *read* a whisper, not who can *create* one. Moderators and admins are an *oversight* audience: they always see whispers so they can review or flag them.
