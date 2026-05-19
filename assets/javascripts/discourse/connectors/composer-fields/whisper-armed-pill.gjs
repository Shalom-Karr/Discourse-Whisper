import Component from "@glimmer/component";
import { action, get } from "@ember/object";
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

  // `whisperTargetUserIds` / `whisperTargetUsernames` are set on the
  // composer model with Ember's `set`. They are not @tracked native
  // fields, so they must be READ with Ember's `get` — that consumes the
  // classic property tag, which is what `set` dirties. A plain
  // `composer.whisperTargetUserIds` access would never re-render the pill.
  get armed() {
    const composer = this.composer;
    return composer
      ? (get(composer, "whisperTargetUserIds") || []).length > 0
      : false;
  }

  get usernames() {
    const composer = this.composer;
    return composer ? get(composer, "whisperTargetUsernames") || [] : [];
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
