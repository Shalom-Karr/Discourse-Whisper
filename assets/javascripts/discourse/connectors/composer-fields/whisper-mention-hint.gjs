import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

// Matches @username tokens in the composer body. Username charset mirrors
// Discourse's default: letters, numbers, underscore, dot, dash, up to 60 chars.
// The (?:^|[\s(]) prefix keeps us from matching email addresses like foo@bar.
const MENTION_RE = /(?:^|[\s(])@([a-zA-Z0-9_.\-]{1,60})/g;

export default class WhisperMentionHint extends Component {
  @tracked resolving = false;

  get composer() {
    return this.args.outletArgs?.model;
  }

  get mentionedUsernames() {
    const raw = this.composer?.reply || "";
    if (!raw.includes("@")) {
      return [];
    }
    const seen = new Set();
    const out = [];
    let match;
    MENTION_RE.lastIndex = 0;
    while ((match = MENTION_RE.exec(raw)) !== null) {
      const u = match[1];
      const key = u.toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        out.push(u);
      }
    }
    return out;
  }

  get alreadyArmedLowercase() {
    const current = this.composer?.whisperTargetUsernames || [];
    return new Set(current.map((u) => u.toLowerCase()));
  }

  get pendingMentions() {
    const mentioned = this.mentionedUsernames;
    if (!mentioned.length) {
      return [];
    }
    const armed = this.alreadyArmedLowercase;
    return mentioned.filter((u) => !armed.has(u.toLowerCase()));
  }

  get isWhisperAlreadyArmed() {
    return (this.composer?.whisperTargetUserIds || []).length > 0;
  }

  get shouldShow() {
    return this.pendingMentions.length > 0;
  }

  get buttonLabel() {
    const names = this.pendingMentions.map((u) => `@${u}`).join(", ");
    return this.isWhisperAlreadyArmed
      ? `Also whisper to ${names}`
      : `Whisper to ${names}`;
  }

  @action
  async armWhisperToMentions() {
    const composer = this.composer;
    if (!composer) {
      return;
    }
    const toResolve = this.pendingMentions;
    if (!toResolve.length) {
      return;
    }

    this.resolving = true;
    try {
      const lookups = await Promise.all(
        toResolve.map((u) =>
          ajax(`/u/${encodeURIComponent(u)}.json`)
            .then((data) => data?.user)
            .catch(() => null)
        )
      );
      const users = lookups.filter(Boolean);
      if (!users.length) {
        return;
      }

      const existingIds = new Set(composer.whisperTargetUserIds || []);
      const existingTargets = [...(composer.whisperTargets || [])];

      users.forEach((u) => {
        if (!existingIds.has(u.id)) {
          existingIds.add(u.id);
          existingTargets.push({
            id: u.id,
            username: u.username,
            avatar_template: u.avatar_template,
          });
        }
      });

      composer.set("whisperTargetUserIds", [...existingIds]);
      composer.set(
        "whisperTargetUsernames",
        existingTargets.map((t) => t.username)
      );
      composer.set("whisperTargets", existingTargets);
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.resolving = false;
    }
  }

  <template>
    {{#if this.shouldShow}}
      <div class="whisper-mention-hint">
        <DButton
          @action={{this.armWhisperToMentions}}
          @disabled={{this.resolving}}
          @icon="far-eye"
          @translatedLabel={{this.buttonLabel}}
          class="btn-small whisper-mention-hint__btn"
        />
      </div>
    {{/if}}
  </template>
}
