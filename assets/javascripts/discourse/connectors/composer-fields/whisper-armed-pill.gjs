import Component from "@glimmer/component";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import { i18n } from "discourse-i18n";

// Renders an indigo pill above the composer body whenever a whisper is armed.
// The pill's DOM presence is ALSO what triggers the indigo tint on the
// surrounding composer fields, via `.composer-fields:has(...)` in SCSS.
//
// Covers three paths that set composer.whisperTargetUserIds:
//   - the toolbar eye button + WhisperTargetModal
//   - the @mention hint connector
//   - the reply auto-arm on `composer:opened`
export default class WhisperArmedPill extends Component {
  get composer() {
    return this.args.outletArgs?.model;
  }

  get armed() {
    return (this.composer?.whisperTargetUserIds || []).length > 0;
  }

  get usernames() {
    return this.composer?.whisperTargetUsernames || [];
  }

  @action
  clearArmed() {
    const composer = this.composer;
    if (!composer) {
      return;
    }
    composer.set("whisperTargetUserIds", null);
    composer.set("whisperTargetUsernames", null);
    composer.set("whisperTargets", null);
  }

  <template>
    {{#if this.armed}}
      <div class="whisper-composer-target-pill" role="status">
        <span class="whisper-composer-target-pill__label">
          {{i18n "discourse_whisper.composer.armed_pill_prefix"}}
        </span>
        <span class="whisper-composer-target-pill__users">
          {{#each this.usernames as |name index|}}
            {{#if index}}<span class="whisper-composer-target-pill__sep">,
              </span>{{/if}}<span
              class="whisper-composer-target-pill__user"
            >@{{name}}</span>
          {{/each}}
        </span>
        <DButton
          @action={{this.clearArmed}}
          @icon="xmark"
          @title="discourse_whisper.composer.clear_armed"
          class="btn-flat whisper-composer-target-pill__close"
        />
      </div>
    {{/if}}
  </template>
}
