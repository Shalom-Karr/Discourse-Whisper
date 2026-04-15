import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { hash } from "@ember/helper";
import DModal from "discourse/components/d-modal";
import DButton from "discourse/components/d-button";
import EmailGroupUserChooser from "select-kit/components/email-group-user-chooser";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import i18n from "discourse-common/helpers/i18n";

export default class WhisperTargetModal extends Component {
  @tracked selection = this.args.model?.composer?.whisperTargetUsername
    ? [this.args.model.composer.whisperTargetUsername]
    : [];
  @tracked saving = false;

  @action
  updateSelection(names) {
    this.selection = names.slice(-1);
  }

  @action
  async confirm() {
    const composer = this.args.model?.composer;
    if (!composer) {
      this.args.closeModal();
      return;
    }

    const username = this.selection[0];
    if (!username) {
      composer.set("whisperTargetUserId", null);
      composer.set("whisperTargetUsername", null);
      composer.set("whisperTargetAvatarTemplate", null);
      this.args.closeModal();
      return;
    }

    this.saving = true;
    try {
      const data = await ajax(`/u/${encodeURIComponent(username)}.json`);
      const u = data?.user;
      if (u) {
        composer.set("whisperTargetUserId", u.id);
        composer.set("whisperTargetUsername", u.username);
        composer.set("whisperTargetAvatarTemplate", u.avatar_template);
      }
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
      composer.set("whisperTargetUserId", null);
      composer.set("whisperTargetUsername", null);
      composer.set("whisperTargetAvatarTemplate", null);
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
            maximum=1
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
