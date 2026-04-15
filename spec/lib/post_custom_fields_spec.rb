# frozen_string_literal: true

require "rails_helper"

RSpec.describe "discourse-whisper post custom fields" do
  fab!(:author) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target) { Fabricate(:user) }
  fab!(:second_target) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: author) }

  before { SiteSetting.discourse_whisper_enabled = true }

  def create_post!(raw:, ids:)
    PostCreator.new(
      author,
      topic_id: topic.id,
      raw: raw,
      whisper_target_user_ids: ids,
    ).create!
  end

  it "stores a single whisper_target_user_ids on post create" do
    post = create_post!(raw: "Whispering to one user, with enough content.", ids: [target.id])
    expect(Array(post.custom_fields["whisper_target_user_ids"]).map(&:to_i)).to eq([target.id])
  end

  it "stores multiple whisper target ids on post create" do
    post =
      create_post!(
        raw: "Whispering to a couple of users, with enough content to pass.",
        ids: [target.id, second_target.id],
      )
    stored = Array(post.custom_fields["whisper_target_user_ids"]).map(&:to_i)
    expect(stored).to contain_exactly(target.id, second_target.id)
  end

  it "filters out ids that do not resolve to real users" do
    post =
      create_post!(
        raw: "One good id and one bogus id in the same whisper request.",
        ids: [target.id, 9_999_999],
      )
    stored = Array(post.custom_fields["whisper_target_user_ids"]).map(&:to_i)
    expect(stored).to eq([target.id])
  end

  it "does not set the custom field when all ids are bogus" do
    post =
      create_post!(
        raw: "Every id is bogus so this should not be a whisper at all.",
        ids: [9_999_999, 9_999_998],
      )
    expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
  end

  it "does not set the custom field when the plugin is disabled" do
    SiteSetting.discourse_whisper_enabled = false
    post =
      create_post!(
        raw: "Plugin disabled path: ids should be ignored entirely here.",
        ids: [target.id],
      )
    expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
  end

  it "ignores non-positive ids" do
    post =
      create_post!(
        raw: "Zero and negative ids should be dropped with the rest.",
        ids: [0, -1],
      )
    expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
  end
end
