# frozen_string_literal: true

module DiscourseWhisper
  module GuardianExtensions
    def can_see_post?(post)
      return super unless SiteSetting.discourse_whisper_enabled
      return super unless post.is_a?(::Post)

      raw_targets = post.custom_fields["whisper_target_user_ids"]
      return super if raw_targets.blank?

      target_ids =
        Array(raw_targets)
          .map { |id| id.is_a?(Numeric) || id.is_a?(String) ? id.to_i : 0 }
          .reject { |id| id <= 0 }
      return super if target_ids.empty?

      # Anonymous / unauthenticated viewers never see whispers
      return false unless authenticated?

      # Author always sees their own whisper
      return super if post.user_id == @user.id
      # Any target recipient sees it
      return super if target_ids.include?(@user.id)
      # Site staff (admins + moderators) see it for oversight
      return super if @user.staff?

      # Category group moderators see it for oversight — UNLESS the whisper
      # is a purely staff-to-staff conversation (admin/mod → admin/mod). In
      # that case, cat group mods have no oversight.
      category = post.topic&.category
      if category && is_category_group_moderator?(category)
        return super unless DiscourseWhisper.staff_to_staff?(post, target_ids)
      end

      false
    end
  end
end
