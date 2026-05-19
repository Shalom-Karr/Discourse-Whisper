import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import { pendingMentions as computePendingMentions } from "../../lib/whisper-mentions";

export default class WhisperMentionHint extends Component {
  @tracked resolving = false;

  get composer() {
    return this.args.outletArgs?.model;
  }

  get pendingMentions() {
    return computePendingMentions(
      this.composer?.reply || "",
      this.composer?.whisperTargetUsernames || []
    );
  }

  get isWhisperAlreadyArmed() {
    return (this.composer?.whisperTargetUserIds || []).length > 0;
  }

  get shouldShow() {
    return this.pendingMentions.length > 0;
  }

  get buttonLabel() {
    const names = this.pendingMentions.map((u) => `@${u}`).join(", ");
    return i18n(
      this.isWhisperAlreadyArmed
        ? "discourse_whisper.mention_hint.also_whisper_to"
        : "discourse_whisper.mention_hint.whisper_to",
      { names }
    );
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
