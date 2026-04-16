# frozen_string_literal: true

module DiscourseWhisper
  # Server-side cap on whisper audience size. Mirrors the client-side
  # `maximum: 10` on the composer's EmailGroupUserChooser so a non-UI client
  # (direct API call, script) can't exceed the intended scope.
  MAX_WHISPER_TARGETS = 10

  # A whisper is "staff-to-staff" when every participant (author + every
  # target) is site staff (admin or moderator). Category group moderators —
  # who are oversight for regular member content — have no oversight over
  # staff-only conversations, so they're excluded from such whispers.
  #
  # This is used both by Guardian (per-post) and by QueryFilter (bulk SQL).
  def self.staff_to_staff?(post, target_ids)
    author = post.user
    return false if author.nil?
    return false unless author.admin? || author.moderator?
    return false if target_ids.blank?

    # If ANY target resolves to a non-staff user, it's not staff-to-staff.
    # Non-resolving target IDs (deleted users) don't flip the answer — they
    # simply don't exist and can't view anything anyway.
    !::User.where(id: target_ids).where("admin = false AND moderator = false").exists?
  end
end
