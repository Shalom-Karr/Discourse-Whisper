# frozen_string_literal: true

module DiscourseWhisper
  module GuardianExtensions
    def can_see_post?(post)
      return super unless SiteSetting.discourse_whisper_enabled
      return super unless post.is_a?(::Post)

      raw_target = post.custom_fields["whisper_target_user_id"]
      return super if raw_target.blank?

      target_id = raw_target.to_i
      return super if target_id <= 0

      # Author always sees their own whisper
      return super if @user && post.user_id == @user.id
      # Target user sees it
      return super if @user && @user.id == target_id
      # Staff always see it (for moderation)
      return super if @user&.staff?
      # Category group moderators see it for oversight
      category = post.topic&.category
      if category && @user && is_category_group_moderator?(category)
        return super
      end

      false
    end
  end
end
