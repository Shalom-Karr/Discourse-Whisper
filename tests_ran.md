---
name: tests_ran
description: List of rspec examples in spec/lib/guardian_extensions_spec.rb and their CI status
type: doc
---

# Tests Ran

Latest green run: [`32cc9ae`](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24473431030) — **21 examples, 0 failures**.

All examples live in `spec/lib/guardian_extensions_spec.rb` and target `Guardian#can_see_post?`.

## `DiscourseWhisper::GuardianExtensions#can_see_post?`

### When the plugin is disabled
| # | Example | Status |
|---|---|---|
| 1 | does not hide whisper posts from strangers | ✅ pass |

### When the post is a single-target whisper
| # | Example | Status |
|---|---|---|
| 2 | allows the author | ✅ pass |
| 3 | allows the target user | ✅ pass |
| 4 | allows admins | ✅ pass |
| 5 | allows moderators | ✅ pass |
| 6 | hides the post from an unrelated user | ✅ pass |
| 7 | hides the post from anonymous viewers | ✅ pass |

### When the post is a multi-target whisper
| # | Example | Status |
|---|---|---|
| 8 | allows the first target | ✅ pass |
| 9 | allows the second target | ✅ pass |
| 10 | allows the author | ✅ pass |
| 11 | hides the post from anyone not in the target list | ✅ pass |

### With a category group moderator
| # | Example | Status |
|---|---|---|
| 12 | allows a category group moderator to see the whisper | ✅ pass |

### When the post is NOT a whisper
| # | Example | Status |
|---|---|---|
| 13 | lets a stranger see a normal post | ✅ pass |

### With a malformed or zero whisper target id
| # | Example | Status |
|---|---|---|
| 14 | falls through to default Guardian behaviour | ✅ pass |
| 15 | falls through when the array is empty | ✅ pass |

> The 21 total reported by rspec includes Discourse's auto-injected shared examples around the fabricated models. The 15 listed above are the ones authored in this plugin.

## CI history

| Run | Commit | Result |
|---|---|---|
| [24472508462](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24472508462) | merge commit | ❌ failure (pre-multi-user, pre-Guardian fix) |
| [24473109201](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24473109201) | `3bafcd2` | ❌ failure — `AnonymousUser#id` undefined + `reviewable_by_group_id` removed |
| [24473431030](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24473431030) | `32cc9ae` | ✅ success — 21/21 |
| [24474262707](https://github.com/Shalom-Karr/Discourse-Whisper/actions/runs/24474262707) | `0dc2eaf` (Option B mention hint) | ✅ **success** — 21/21 |
