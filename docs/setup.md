# Setup & Installation

## Installation

Add the plugin's repository URL to your container's `app.yml`:

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

## Configuration

All settings are under **Admin → Site Settings → Discourse Whisper**.

| Setting | Default | Description |
|---|---|---|
| `discourse_whisper_enabled` | `true` | Master switch for the plugin. When off, the toolbar button is hidden and the guardian extension stops hiding whisper posts. Existing whisper custom fields are preserved on disk but no longer acted on. |

## Enabling the plugin

1. Go to **Admin → Site Settings**
2. Search for `discourse_whisper_enabled`
3. Confirm it is set to **true** (it defaults to true on install)

## Who can whisper?

Any user who can post is able to mark a post as a whisper — there is no additional trust level or group gate. The visibility rules (see [whispers.md](whispers.md)) enforce who can *read* a whisper, not who can *create* one.

## Category group moderator oversight

If you use Discourse's [category group moderators](https://meta.discourse.org/t/category-group-moderators/175310) feature (set via **Category → Settings → Reviewable by group**), those users automatically gain read access to every whisper in that category. That is how a community can give trusted users moderation oversight of whispers without making them site-wide staff.
