# frozen_string_literal: true

require "rails_helper"

RSpec.describe "discourse-whisper post custom fields" do
  fab!(:author) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: author) }

  before { SiteSetting.discourse_whisper_enabled = true }

  it "stores whisper_target_user_id on post create when provided" do
    creator =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "This is a whisper to the target user, with enough content to validate.",
        whisper_target_user_id: target.id,
      )
    post = creator.create!
    expect(post.custom_fields["whisper_target_user_id"].to_i).to eq(target.id)
  end

  it "ignores a whisper_target_user_id that does not resolve to a real user" do
    creator =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "This should not become a whisper because the target id is bogus.",
        whisper_target_user_id: 9_999_999,
      )
    post = creator.create!
    expect(post.custom_fields["whisper_target_user_id"]).to be_blank
  end

  it "does not set the custom field when the plugin is disabled" do
    SiteSetting.discourse_whisper_enabled = false
    creator =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Plugin disabled path: target id should be ignored entirely.",
        whisper_target_user_id: target.id,
      )
    post = creator.create!
    expect(post.custom_fields["whisper_target_user_id"]).to be_blank
  end

  it "ignores a non-positive whisper_target_user_id" do
    creator =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Zero target id should be a no-op for the whisper plugin.",
        whisper_target_user_id: 0,
      )
    post = creator.create!
    expect(post.custom_fields["whisper_target_user_id"]).to be_blank
  end
end
