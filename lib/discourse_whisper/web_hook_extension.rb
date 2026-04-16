# frozen_string_literal: true

module DiscourseWhisper
  # Whisper posts must not be sent to webhook URLs. `WebHook.enqueue_post_hooks`
  # is the single enqueue point for post-related webhook events (`post_created`,
  # `post_edited`, `post_destroyed`, `post_recovered`) — prepending here drops
  # the event for any post that has a `whisper_target_user_ids` custom field.
  #
  # This is a hard block, not a redaction: the whisper is never sent to the
  # webhook URL at all. Admins who need webhooks that include whispers would
  # have to disable the plugin.
  module WebHookExtension
    def enqueue_post_hooks(event, post, payload = nil)
      if SiteSetting.discourse_whisper_enabled && post &&
           post.custom_fields["whisper_target_user_ids"].present?
        return
      end
      super
    end
  end
end
