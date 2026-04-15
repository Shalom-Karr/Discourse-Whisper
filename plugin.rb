# frozen_string_literal: true

# name: discourse-whisper
# about: Per-user private whisper posts visible only to chosen target users, category moderators, and staff
# version: 0.1.0
# authors: Nate Karr
# required_version: 2.7.0
# enabled_site_setting: discourse_whisper_enabled

register_asset "stylesheets/discourse-whisper.scss"

require_relative "lib/discourse_whisper/guardian_extensions"

after_initialize do
  register_post_custom_field_type("whisper_target_user_ids", :json)
  add_permitted_post_create_param(:whisper_target_user_ids, :array)

  reloadable_patch { ::Guardian.prepend(DiscourseWhisper::GuardianExtensions) }

  on(:post_created) do |post, opts, _user|
    next unless SiteSetting.discourse_whisper_enabled

    raw = opts[:whisper_target_user_ids]
    ids = Array(raw).map { |v| v.to_i }.reject { |i| i <= 0 }.uniq
    next if ids.empty?

    valid_ids = ::User.where(id: ids).pluck(:id)
    next if valid_ids.empty?

    post.custom_fields["whisper_target_user_ids"] = valid_ids
    post.save_custom_fields
  end

  add_to_serializer(:post, :is_whisper_to_user) do
    object.custom_fields["whisper_target_user_ids"].present?
  end
  add_to_serializer(:post, :include_is_whisper_to_user?) do
    SiteSetting.discourse_whisper_enabled
  end

  add_to_serializer(:post, :whisper_target_user_ids) do
    Array(object.custom_fields["whisper_target_user_ids"]).map(&:to_i)
  end
  add_to_serializer(:post, :include_whisper_target_user_ids?) do
    SiteSetting.discourse_whisper_enabled &&
      object.custom_fields["whisper_target_user_ids"].present?
  end

  add_to_serializer(:post, :whisper_targets) do
    ids = Array(object.custom_fields["whisper_target_user_ids"]).map(&:to_i)
    ::User
      .where(id: ids)
      .map do |u|
        { id: u.id, username: u.username, avatar_template: u.avatar_template }
      end
  end
  add_to_serializer(:post, :include_whisper_targets?) do
    SiteSetting.discourse_whisper_enabled &&
      object.custom_fields["whisper_target_user_ids"].present?
  end
end
