# frozen_string_literal: true

require "rails_helper"

RSpec.describe "discourse-whisper TopicView post stream filtering" do
  fab!(:author, :user)
  fab!(:target, :user)
  fab!(:second_target, :user)
  fab!(:stranger, :user)
  fab!(:admin)
  fab!(:moderator)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, user: author) }

  # A topic with: normal -> whisper(target) -> normal -> whisper(target, second_target) -> normal
  fab!(:first_post) { Fabricate(:post, topic: topic, user: author, post_number: 1) }
  fab!(:whisper) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end
  fab!(:middle_post) { Fabricate(:post, topic: topic, user: author) }
  fab!(:multi_whisper) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_ids"] = [target.id, second_target.id]
    post.save_custom_fields
    post
  end
  fab!(:last_post) { Fabricate(:post, topic: topic, user: author) }

  before { SiteSetting.discourse_whisper_enabled = true }

  def visible_post_ids(user)
    TopicView.new(topic.id, user).posts.map(&:id)
  end

  describe "a stranger" do
    it "does not see any whisper post in the stream" do
      ids = visible_post_ids(stranger)
      expect(ids).not_to include(whisper.id)
      expect(ids).not_to include(multi_whisper.id)
    end

    it "still sees every non-whisper post in the stream" do
      ids = visible_post_ids(stranger)
      expect(ids).to include(first_post.id, middle_post.id, last_post.id)
    end
  end

  describe "an anonymous viewer" do
    it "does not see any whisper post" do
      ids = visible_post_ids(nil)
      expect(ids).not_to include(whisper.id)
      expect(ids).not_to include(multi_whisper.id)
    end
  end

  describe "the author" do
    it "sees both whisper posts and all normal posts" do
      ids = visible_post_ids(author)
      expect(ids).to include(
        first_post.id,
        whisper.id,
        middle_post.id,
        multi_whisper.id,
        last_post.id,
      )
    end
  end

  describe "the single target" do
    it "sees the single-target whisper and the multi-target whisper" do
      ids = visible_post_ids(target)
      expect(ids).to include(whisper.id, multi_whisper.id)
    end
  end

  describe "a secondary target who is only in the multi whisper" do
    it "sees the multi whisper but NOT the single-target whisper" do
      ids = visible_post_ids(second_target)
      expect(ids).to include(multi_whisper.id)
      expect(ids).not_to include(whisper.id)
    end
  end

  describe "an admin" do
    it "sees every whisper for oversight" do
      ids = visible_post_ids(admin)
      expect(ids).to include(whisper.id, multi_whisper.id)
    end
  end

  describe "a moderator" do
    it "sees every whisper for oversight" do
      ids = visible_post_ids(moderator)
      expect(ids).to include(whisper.id, multi_whisper.id)
    end
  end

  describe "a category group moderator" do
    fab!(:cat_mod_group, :group)
    fab!(:cat_mod_user, :user)

    before do
      SiteSetting.enable_category_group_moderation = true
      cat_mod_group.add(cat_mod_user)
      ::CategoryModerationGroup.create!(category_id: category.id, group_id: cat_mod_group.id)
      category.reload
    end

    it "sees every whisper in their category" do
      ids = visible_post_ids(cat_mod_user)
      expect(ids).to include(whisper.id, multi_whisper.id)
    end

    it "does NOT see whispers in categories they don't moderate" do
      other_cat = Fabricate(:category)
      other_topic = Fabricate(:topic, category: other_cat, user: author)
      Fabricate(:post, topic: other_topic, user: author)
      other_whisper = Fabricate(:post, topic: other_topic, user: author)
      other_whisper.custom_fields["whisper_target_user_ids"] = [target.id]
      other_whisper.save_custom_fields

      ids = TopicView.new(other_topic.id, cat_mod_user).posts.map(&:id)
      expect(ids).not_to include(other_whisper.id)
    end
  end

  describe "when the plugin is disabled" do
    before { SiteSetting.discourse_whisper_enabled = false }

    it "lets a stranger see every post including whispers" do
      ids = visible_post_ids(stranger)
      expect(ids).to include(whisper.id, multi_whisper.id)
    end
  end

  describe "post count bookkeeping" do
    it "reflects the filtered count for a stranger (< total posts)" do
      stranger_count = TopicView.new(topic.id, stranger).posts.size
      author_count = TopicView.new(topic.id, author).posts.size
      expect(stranger_count).to be < author_count
    end
  end

  describe "with explicit post_ids option" do
    it "stranger requesting a specific whisper id receives nothing" do
      tv = TopicView.new(topic.id, stranger, post_ids: [whisper.id])
      expect(tv.posts.map(&:id)).not_to include(whisper.id)
    end

    it "target requesting a specific whisper id receives the post" do
      tv = TopicView.new(topic.id, target, post_ids: [whisper.id])
      expect(tv.posts.map(&:id)).to include(whisper.id)
    end
  end

  describe "print mode" do
    it "stranger's print view excludes whispers" do
      tv = TopicView.new(topic.id, stranger, print: true)
      expect(tv.posts.map(&:id)).not_to include(whisper.id)
    end
  end
end
