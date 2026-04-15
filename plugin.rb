# frozen_string_literal: true

# name: discourse-whisper
# about: Per-user private whisper posts visible only to the target user, category moderators, and staff
# version: 0.1.0
# authors: Nate Karr
# required_version: 2.7.0
# enabled_site_setting: discourse_whisper_enabled

register_asset "stylesheets/discourse-whisper.scss"

require_relative "lib/discourse_whisper/guardian_extensions"

after_initialize do
  register_post_custom_field_type("whisper_target_user_id", :integer)
  add_permitted_post_create_param(:whisper_target_user_id)

  reloadable_patch { ::Guardian.prepend(DiscourseWhisper::GuardianExtensions) }

  on(:post_created) do |post, opts, _user|
    next unless SiteSetting.discourse_whisper_enabled
    target_id = opts[:whisper_target_user_id].to_i
    next if target_id <= 0
    next unless ::User.where(id: target_id).exists?

    post.custom_fields["whisper_target_user_id"] = target_id
    post.save_custom_fields
  end

  add_to_serializer(:post, :is_whisper_to_user) do
    object.custom_fields["whisper_target_user_id"].present?
  end
  add_to_serializer(:post, :include_is_whisper_to_user?) do
    SiteSetting.discourse_whisper_enabled
  end

  add_to_serializer(:post, :whisper_target_user_id) do
    object.custom_fields["whisper_target_user_id"]&.to_i
  end
  add_to_serializer(:post, :include_whisper_target_user_id?) do
    SiteSetting.discourse_whisper_enabled &&
      object.custom_fields["whisper_target_user_id"].present?
  end

  add_to_serializer(:post, :whisper_target_username) do
    id = object.custom_fields["whisper_target_user_id"]&.to_i
    ::User.where(id: id).pluck(:username).first
  end
  add_to_serializer(:post, :include_whisper_target_username?) do
    SiteSetting.discourse_whisper_enabled &&
      object.custom_fields["whisper_target_user_id"].present?
  end

  add_to_serializer(:post, :whisper_target_avatar_template) do
    id = object.custom_fields["whisper_target_user_id"]&.to_i
    ::User.find_by(id: id)&.avatar_template
  end
  add_to_serializer(:post, :include_whisper_target_avatar_template?) do
    SiteSetting.discourse_whisper_enabled &&
      object.custom_fields["whisper_target_user_id"].present?
  end
end
