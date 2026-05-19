# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "discourse-whisper post custom fields" do
  fab!(:author) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target, :user)
  fab!(:second_target, :user)
  fab!(:third_target, :user)
  fab!(:topic) { Fabricate(:topic, user: author) }

  before { SiteSetting.discourse_whisper_enabled = true }

  def create_post!(raw:, ids:)
    PostCreator.new(author, topic_id: topic.id, raw: raw, whisper_target_user_ids: ids).create!
  end

  def stored_ids(post)
    Array(post.custom_fields["whisper_target_user_ids"]).map(&:to_i)
  end

  it "stores a single whisper_target_user_ids on post create" do
    post = create_post!(raw: "Whispering to one user, with enough content.", ids: [target.id])
    expect(stored_ids(post)).to eq([target.id])
  end

  it "stores multiple whisper target ids on post create" do
    post =
      create_post!(
        raw: "Whispering to a couple of users, with enough content to pass.",
        ids: [target.id, second_target.id],
      )
    expect(stored_ids(post)).to contain_exactly(target.id, second_target.id)
  end

  it "filters out ids that do not resolve to real users" do
    post =
      create_post!(
        raw: "One good id and one bogus id in the same whisper request.",
        ids: [target.id, 9_999_999],
      )
    expect(stored_ids(post)).to eq([target.id])
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
    post = create_post!(raw: "Zero and negative ids should be dropped with the rest.", ids: [0, -1])
    expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
  end

  it "deduplicates repeated ids in the input" do
    post =
      create_post!(
        raw: "Same id repeated should only be stored once in the field.",
        ids: [target.id, target.id, target.id],
      )
    expect(stored_ids(post)).to eq([target.id])
  end

  it "accepts string ids and coerces them to integers" do
    post =
      create_post!(
        raw: "Strings should be coerced to ints in the same field path.",
        ids: [target.id.to_s, second_target.id.to_s],
      )
    expect(stored_ids(post)).to contain_exactly(target.id, second_target.id)
  end

  it "filters out a mix of valid, invalid, zero, negative and bogus string ids" do
    post =
      create_post!(
        raw: "Mixed bag of ids — only the valid ones should make it through.",
        ids: [target.id, 0, -1, "abc", "42abc", 9_999_999, second_target.id.to_s],
      )
    expect(stored_ids(post)).to contain_exactly(target.id, second_target.id)
  end

  it "does not set the custom field when ids is nil" do
    post =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "No ids passed at all — this is a normal non-whisper post.",
        whisper_target_user_ids: nil,
      ).create!
    expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
  end

  it "does not set the custom field when ids is omitted entirely" do
    post =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Nothing related to whispers in this post create payload at all.",
      ).create!
    expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
  end

  it "does not set the custom field when ids is an empty array" do
    post = create_post!(raw: "Empty whisper id array — should be a normal post here.", ids: [])
    expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
  end

  it "accepts a single (non-array) id by wrapping it" do
    post =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "A single scalar id, not in an array — should still be wrapped.",
        whisper_target_user_ids: target.id,
      ).create!
    expect(stored_ids(post)).to eq([target.id])
  end

  it "stores audiences up to the server-side cap without truncation" do
    extras = Array.new(5) { Fabricate(:user) }
    ids = [target.id, second_target.id, third_target.id, *extras.map(&:id)]
    post = create_post!(raw: "Whispering to a larger audience of more than three users.", ids: ids)
    expect(stored_ids(post)).to contain_exactly(*ids)
  end

  it "caps the audience at DiscourseWhisper::MAX_WHISPER_TARGETS (10) on the server side" do
    extras = Array.new(15) { Fabricate(:user) }
    post =
      create_post!(
        raw: "Big audience: more than the server-side cap of ten users.",
        ids: extras.map(&:id),
      )
    expect(stored_ids(post).length).to eq(DiscourseWhisper::MAX_WHISPER_TARGETS)
    # The cap keeps the first N unique valid IDs (insertion order).
    expect(stored_ids(post)).to eq(extras.first(DiscourseWhisper::MAX_WHISPER_TARGETS).map(&:id))
  end

  it "MAX_WHISPER_TARGETS is 10 (lock the value)" do
    expect(DiscourseWhisper::MAX_WHISPER_TARGETS).to eq(10)
  end

  it "handles floats by truncating them to integer ids" do
    post =
      create_post!(
        raw: "Whisper with float-ish ids — integer truncation should kick in.",
        ids: [target.id.to_f, 0.5, -1.2],
      )
    expect(stored_ids(post)).to eq([target.id])
  end

  it "ignores nil entries in the input array" do
    post =
      create_post!(
        raw: "Whisper with nils — they should be coerced to zero and dropped.",
        ids: [nil, target.id, nil, second_target.id],
      )
    expect(stored_ids(post)).to contain_exactly(target.id, second_target.id)
  end

  it "allows the author to whisper to themselves (self-target)" do
    post =
      create_post!(
        raw: "Author is also a target — should be stored since they're a real user.",
        ids: [author.id, target.id],
      )
    expect(stored_ids(post)).to contain_exactly(author.id, target.id)
  end

  it "accepts targets who are suspended users (still real Users)" do
    suspended = Fabricate(:user, suspended_till: 10.days.from_now, suspended_at: Time.now)
    post =
      create_post!(
        raw: "Whisper to a suspended user — they're still a valid User record.",
        ids: [suspended.id],
      )
    expect(stored_ids(post)).to eq([suspended.id])
  end

  it "does NOT modify the custom field on post edit (no :post_edited listener)" do
    post = create_post!(raw: "Initial whisper text, with enough content to pass.", ids: [target.id])
    original_ids = stored_ids(post)

    revisor = PostRevisor.new(post)
    revisor.revise!(author, raw: "Edited whisper text, still long enough for Discourse to accept.")
    post.reload

    # Edits are a no-op for the whisper audience: still the original set.
    expect(stored_ids(post)).to eq(original_ids)
  end

  it "persists the custom field across a reload from the database" do
    post =
      create_post!(
        raw: "Whisper that we will reload from the database just to be sure.",
        ids: [target.id],
      )
    fresh = Post.find(post.id)
    expect(Array(fresh.custom_fields["whisper_target_user_ids"]).map(&:to_i)).to eq([target.id])
  end

  it "creates a whisper in a PM topic when the target is a PM participant" do
    pm = Fabricate(:private_message_topic, user: author, topic_allowed_users: [])
    TopicAllowedUser.create!(topic: pm, user: author)
    TopicAllowedUser.create!(topic: pm, user: target)

    post =
      PostCreator.new(
        author,
        topic_id: pm.id,
        raw: "Whispering inside a PM topic — same custom field path applies here too.",
        whisper_target_user_ids: [target.id],
      ).create!

    expect(stored_ids(post)).to eq([target.id])
  end

  it "serializes the custom field on the post after reload through PostSerializer" do
    post =
      create_post!(
        raw: "Whisper whose custom field we then read through the post serializer.",
        ids: [target.id],
      )
    post.reload
    serialized = PostSerializer.new(post, scope: Guardian.new(author), root: false).as_json
    expect(serialized[:is_whisper_to_user]).to eq(true)
    expect(serialized[:whisper_target_user_ids]).to contain_exactly(target.id)
  end

  it "does not reject when author is also the only target" do
    post =
      create_post!(
        raw: "Whispering to myself only — valid because author is a real user.",
        ids: [author.id],
      )
    expect(stored_ids(post)).to eq([author.id])
  end

  it "drops non-integer-coercible types (hashes) from the input without crashing" do
    # Hash doesn't respond to #to_i. The plugin must not raise on oddly-shaped
    # inputs; it uses a defensive `respond_to?(:to_i)` coercion so bad entries
    # are silently dropped.
    post =
      create_post!(
        raw: "Mixed payload with a sneaky hash — bad entries should be dropped not raise.",
        ids: [target.id, { "sneaky" => "value" }],
      )
    expect(stored_ids(post)).to eq([target.id])
  end

  it "drops symbols from the input without crashing" do
    post =
      create_post!(
        raw: "Symbols should be dropped — they're not a realistic payload but must not crash.",
        ids: [target.id, :bogus_symbol],
      )
    expect(stored_ids(post)).to eq([target.id])
  end

  it "drops arrays (nested) from the input without crashing" do
    post =
      create_post!(
        raw: "Nested arrays should not crash the post create path when they sneak in.",
        ids: [target.id, [1, 2, 3]],
      )
    expect(stored_ids(post)).to eq([target.id])
  end
end
# rubocop:enable RSpec/DescribeClass
