# frozen_string_literal: true

# name: discourse-whisper
# about: Per-user private whisper posts visible only to chosen target users, category moderators, and staff
# version: 0.1.0
# authors: Shalom Karr and Avrumi Sternheim
# required_version: 2.7.0
# enabled_site_setting: discourse_whisper_enabled

register_asset "stylesheets/discourse-whisper.scss"

require_relative "lib/discourse_whisper/staff_visibility"
require_relative "lib/discourse_whisper/guardian_extensions"
require_relative "lib/discourse_whisper/query_filter"
require_relative "lib/discourse_whisper/search_extension"
require_relative "lib/discourse_whisper/web_hook_extension"

after_initialize do
  register_post_custom_field_type("whisper_target_user_ids", :json)
  add_permitted_post_create_param(:whisper_target_user_ids, :array)

  reloadable_patch { ::Guardian.prepend(DiscourseWhisper::GuardianExtensions) }
  reloadable_patch { ::Search.prepend(DiscourseWhisper::SearchExtension) }
  reloadable_patch { ::WebHook.singleton_class.prepend(DiscourseWhisper::WebHookExtension) }

  TopicView.apply_custom_default_scope do |scope, tv|
    DiscourseWhisper::QueryFilter.apply(scope, tv.guardian&.user)
  end

  # We hook `:before_create_post` (not `:post_created`) so the custom field
  # is in place on the post instance BEFORE `@post.save!` runs in PostCreator.
  # The post's `after_save` callback (HasCustomFields) persists the custom
  # field atomically with the save, which means any downstream listener on
  # `:post_created` — notably Discourse's webhook dispatcher — sees the
  # whisper marker on the post and can short-circuit (see WebHookExtension).
  on(:before_create_post) do |post, opts|
    next unless SiteSetting.discourse_whisper_enabled

    raw = opts[:whisper_target_user_ids]
    ids =
      Array(raw)
        .map { |v| v.is_a?(Numeric) || v.is_a?(String) ? v.to_i : 0 }
        .reject { |i| i <= 0 }
        .uniq
        .first(DiscourseWhisper::MAX_WHISPER_TARGETS)
    next if ids.empty?

    valid_ids = ::User.where(id: ids).pluck(:id)
    next if valid_ids.empty?

    post.custom_fields["whisper_target_user_ids"] = valid_ids
    # Do not call save_custom_fields here — the post is still unsaved.
    # HasCustomFields' `after_save` callback will persist on `@post.save!`.
  end

  add_to_serializer(:post, :is_whisper_to_user) do
    object.custom_fields["whisper_target_user_ids"].present?
  end
  add_to_serializer(:post, :include_is_whisper_to_user?) { SiteSetting.discourse_whisper_enabled }

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
      .map { |u| { id: u.id, username: u.username, avatar_template: u.avatar_template } }
  end
  add_to_serializer(:post, :include_whisper_targets?) do
    SiteSetting.discourse_whisper_enabled &&
      object.custom_fields["whisper_target_user_ids"].present?
  end
end
