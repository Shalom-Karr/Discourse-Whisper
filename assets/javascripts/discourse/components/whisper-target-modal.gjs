import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import EmailGroupUserChooser from "discourse/select-kit/components/email-group-user-chooser";
import { i18n } from "discourse-i18n";

export default class WhisperTargetModal extends Component {
  @tracked
  selection = Array.isArray(this.args.model?.composer?.whisperTargetUsernames)
    ? [...this.args.model.composer.whisperTargetUsernames]
    : [];
  @tracked saving = false;

  @action
  updateSelection(names) {
    this.selection = names;
  }

  @action
  async confirm() {
    const composer = this.args.model?.composer;
    if (!composer) {
      this.args.closeModal();
      return;
    }

    if (!this.selection.length) {
      composer.set("whisperTargetUserIds", null);
      composer.set("whisperTargetUsernames", null);
      composer.set("whisperTargets", null);
      this.args.closeModal();
      return;
    }

    this.saving = true;
    try {
      const lookups = await Promise.all(
        this.selection.map((username) =>
          ajax(`/u/${encodeURIComponent(username)}.json`)
            .then((data) => data?.user)
            .catch(() => null)
        )
      );
      const users = lookups.filter(Boolean);
      composer.set(
        "whisperTargetUserIds",
        users.map((u) => u.id)
      );
      composer.set(
        "whisperTargetUsernames",
        users.map((u) => u.username)
      );
      composer.set(
        "whisperTargets",
        users.map((u) => ({
          id: u.id,
          username: u.username,
          avatar_template: u.avatar_template,
        }))
      );
      this.args.closeModal();
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.saving = false;
    }
  }

  @action
  clear() {
    const composer = this.args.model?.composer;
    if (composer) {
      composer.set("whisperTargetUserIds", null);
      composer.set("whisperTargetUsernames", null);
      composer.set("whisperTargets", null);
    }
    this.args.closeModal();
  }

  <template>
    <DModal
      @title={{i18n "discourse_whisper.composer.modal_title"}}
      @closeModal={{@closeModal}}
      class="whisper-target-modal"
    >
      <:body>
        <p class="whisper-target-modal__instructions">
          {{i18n "discourse_whisper.composer.modal_instructions"}}
        </p>
        <EmailGroupUserChooser
          @value={{this.selection}}
          @onChange={{this.updateSelection}}
          @options={{hash
            maximum=10
            includeGroups=false
            filterPlaceholder="discourse_whisper.composer.search_placeholder"
          }}
        />
      </:body>
      <:footer>
        <DButton
          @action={{this.confirm}}
          @label="discourse_whisper.composer.confirm"
          @disabled={{this.saving}}
          class="btn-primary"
        />
        <DButton
          @action={{this.clear}}
          @label="discourse_whisper.composer.clear_target"
        />
      </:footer>
    </DModal>
  </template>
}
