# frozen_string_literal: true

require "rails_helper"

# Edge case: users who cannot see a whisper must not be able to interact with
# it in ways that might leak content (liking, bookmarking, quoting).
RSpec.describe "discourse-whisper interaction surface" do
  fab!(:author) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:stranger) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:admin)
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:whisper) do
    post =
      Fabricate(:post, topic: topic, user: author, raw: "Body for interaction surface testing.")
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end

  before { SiteSetting.discourse_whisper_enabled = true }

  describe "bookmarks" do
    it "cannot be created by a stranger (they cannot see the post)" do
      # Bookmark creation requires can_see_post? on the bookmarkable.
      expect(Guardian.new(stranger).can_see_post?(whisper)).to eq(false)
    end

    it "can be created by the target" do
      expect(Guardian.new(target).can_see_post?(whisper)).to eq(true)
      bookmark = Bookmark.new(user: target, bookmarkable: whisper, name: "test")
      expect(bookmark).to be_valid
    end

    it "can be created by the author" do
      bookmark = Bookmark.new(user: author, bookmarkable: whisper, name: "test")
      expect(bookmark).to be_valid
    end
  end

  describe "likes / reactions" do
    it "a stranger cannot like a post they can't see" do
      expect(Guardian.new(stranger).can_see_post?(whisper)).to eq(false)
    end

    it "the target can like the whisper" do
      expect(Guardian.new(target).post_can_act?(whisper, :like)).to eq(true)
    end
  end
end
