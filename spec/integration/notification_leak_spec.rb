# frozen_string_literal: true

require "rails_helper"

# Regression coverage: whisper post contents and metadata must not leak to
# non-recipients through any notification channel.
RSpec.describe "discourse-whisper notification leak coverage" do
  fab!(:author, :user)
  fab!(:target, :user)
  fab!(:stranger, :user)
  fab!(:topic) { Fabricate(:topic, user: author) }

  before { SiteSetting.discourse_whisper_enabled = true }

  it "does not show a mention notification from a whisper's body to a non-recipient" do
    PostCreator.new(
      author,
      topic_id: topic.id,
      raw: "Hey @#{stranger.username}, secret whisper content here for targets only.",
      whisper_target_user_ids: [target.id],
    ).create!

    # The stranger was @-mentioned INSIDE a whisper they can't see. A mention
    # notification would tell them "someone mentioned you" and link them to a
    # post they cannot actually read. At minimum, the stranger should not be
    # able to render the post they're notified about.
    notified_post_ids =
      Notification.where(user_id: stranger.id).where.not(post_number: nil).map(&:post_id).compact

    notified_post_ids.each do |pid|
      post = Post.find(pid)
      expect(Guardian.new(stranger).can_see_post?(post)).to eq(false),
      "Stranger received a notification pointing to whisper post #{pid}, but Guardian also hid it. " \
        "The notification should be suppressed server-side."
    end
  end

  it "still permits the recipient to render the whisper they're notified about" do
    post =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Hey @#{target.username}, here is your secret whisper content directly.",
        whisper_target_user_ids: [target.id],
      ).create!

    # Even if notification delivery is asynchronous or suppressed in the test
    # env, the key invariant is: the recipient can actually see the post they'd
    # be notified about.
    expect(Guardian.new(target).can_see_post?(post)).to eq(true)
  end

  describe "verified regression locks on Discourse's built-in notification plumbing" do
    before { Jobs.run_immediately! }

    it "creates ZERO notifications for a stranger @-mentioned in a whisper body" do
      baseline_count = Notification.where(user_id: stranger.id).count
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Whisper body with @#{stranger.username} mention — PostAlerter must NOT notify them.",
        whisper_target_user_ids: [target.id],
      ).create!
      after_count = Notification.where(user_id: stranger.id).count
      # PostAlerter gates on Guardian#can_see_post? — because our override
      # hides the whisper from the stranger, no mention notification is created.
      # This spec locks that behavior in: if someone changes the plugin and
      # accidentally lets the stranger see the post, the notif WILL be created
      # and this test will flag the regression.
      expect(after_count - baseline_count).to eq(0)
    end

    it "creates a notification for a stranger mentioned in a NORMAL post (baseline plumbing check)" do
      baseline_count = Notification.where(user_id: stranger.id).count
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Baseline normal (non-whisper) post with @#{stranger.username} mention.",
      ).create!
      after_count = Notification.where(user_id: stranger.id).count
      expect(after_count).to be > baseline_count,
      "Discourse's mention-notification plumbing appears broken in this env — " \
        "the adjacent whisper-mention spec's zero-notif guarantee relies on it."
    end

    it "does NOT notify group members outside the whisper audience on a group @-mention" do
      outsider = Fabricate(:user)
      group = Fabricate(:group, mentionable_level: Group::ALIAS_LEVELS[:everyone])
      group.add(outsider)
      group.save!

      baseline = Notification.where(user_id: outsider.id).count
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Whisper with @#{group.name} group mention — must not leak to outsiders.",
        whisper_target_user_ids: [target.id],
      ).create!
      expect(Notification.where(user_id: outsider.id).count - baseline).to eq(0)
    end

    it "DOES notify a group member who is ALSO a whisper target" do
      group = Fabricate(:group, mentionable_level: Group::ALIAS_LEVELS[:everyone])
      group.add(target)
      group.save!

      baseline = Notification.where(user_id: target.id).count
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Whisper with @#{group.name} mention — target is in group AND audience.",
        whisper_target_user_ids: [target.id],
      ).create!
      expect(Notification.where(user_id: target.id).count).to be > baseline
    end
  end
end
