# frozen_string_literal: true

module DiscourseWhisper
  module GuardianExtensions
    def can_see_post?(post)
      return super unless SiteSetting.discourse_whisper_enabled
      return super unless post.is_a?(::Post)

      raw_targets = post.custom_fields["whisper_target_user_ids"]
      return super if raw_targets.blank?

      target_ids = Array(raw_targets).map(&:to_i).reject { |id| id <= 0 }
      return super if target_ids.empty?

      # Anonymous / unauthenticated viewers never see whispers
      return false unless authenticated?

      # Author always sees their own whisper
      return super if post.user_id == @user.id
      # Any target recipient sees it
      return super if target_ids.include?(@user.id)
      # Site staff see it for oversight
      return super if @user.staff?
      # Category group moderators see it for oversight
      category = post.topic&.category
      return super if category && is_category_group_moderator?(category)

      false
    end
  end
end
