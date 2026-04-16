# frozen_string_literal: true

require "rails_helper"

# Regression coverage: the plugin must NOT change Discourse's default behavior
# for non-whisper content. Every hook must short-circuit cleanly when a post
# has no whisper custom field, when the plugin is disabled, or when the
# viewer is staff.
RSpec.describe "discourse-whisper no-regression coverage" do
  fab!(:author) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:other_user, :user)
  fab!(:stranger, :user)
  fab!(:admin)
  fab!(:moderator)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, user: author) }
  fab!(:normal_post_a) { Fabricate(:post, topic: topic, user: author) }
  fab!(:normal_post_b) { Fabricate(:post, topic: topic, user: other_user) }
  fab!(:normal_post_c) { Fabricate(:post, topic: topic, user: author) }

  before { SiteSetting.discourse_whisper_enabled = true }

  describe "Guardian#can_see_post? on non-whisper posts" do
    it "behaves identically to core for a stranger viewing a normal post" do
      expect(Guardian.new(stranger).can_see_post?(normal_post_a)).to eq(true)
    end

    it "behaves identically to core for the author viewing their own post" do
      expect(Guardian.new(author).can_see_post?(normal_post_a)).to eq(true)
    end

    it "behaves identically to core for an anonymous viewer" do
      expect(Guardian.new(nil).can_see_post?(normal_post_a)).to eq(true)
    end

    it "behaves identically to core when plugin is disabled" do
      SiteSetting.discourse_whisper_enabled = false
      expect(Guardian.new(stranger).can_see_post?(normal_post_a)).to eq(true)
    end
  end

  describe "TopicView on a topic with no whispers" do
    it "shows all normal posts to a stranger" do
      ids = TopicView.new(topic.id, stranger).posts.map(&:id)
      expect(ids).to include(normal_post_a.id, normal_post_b.id, normal_post_c.id)
    end

    it "shows all normal posts to an anonymous viewer" do
      ids = TopicView.new(topic.id, nil).posts.map(&:id)
      expect(ids).to include(normal_post_a.id, normal_post_b.id, normal_post_c.id)
    end

    it "shows the same post count whether plugin is enabled or disabled" do
      enabled = TopicView.new(topic.id, stranger).posts.size
      SiteSetting.discourse_whisper_enabled = false
      disabled = TopicView.new(topic.id, stranger).posts.size
      expect(enabled).to eq(disabled)
    end
  end

  describe "Search on content with no whispers" do
    fab!(:indexable_post) do
      post =
        Fabricate(
          :post,
          topic: topic,
          user: author,
          raw: "Regression needle nrneedle7xyz searchable content for the non-whisper baseline.",
        )
      SearchIndexer.enable
      SearchIndexer.index(post, force: true)
      post
    end

    it "finds normal posts for a stranger without any whisper filtering side-effect" do
      results = Search.execute("nrneedle7xyz", guardian: Guardian.new(stranger))
      expect(results.posts.map(&:id)).to include(indexable_post.id)
    end
  end

  describe "QueryFilter short-circuits" do
    it "returns the scope unchanged when plugin is disabled" do
      SiteSetting.discourse_whisper_enabled = false
      scope = Post.where(user_id: author.id)
      filtered = DiscourseWhisper::QueryFilter.apply(scope, stranger)
      expect(filtered.to_a).to eq(scope.to_a)
    end

    it "returns the scope unchanged when viewer is an admin" do
      scope = Post.where(user_id: author.id)
      filtered = DiscourseWhisper::QueryFilter.apply(scope, admin)
      expect(filtered.to_a).to eq(scope.to_a)
    end

    it "returns the scope unchanged when viewer is a moderator" do
      scope = Post.where(user_id: author.id)
      filtered = DiscourseWhisper::QueryFilter.apply(scope, moderator)
      expect(filtered.to_a).to eq(scope.to_a)
    end
  end

  describe "post_created handler on non-whisper posts" do
    it "does not touch custom_fields for a regular post" do
      post =
        PostCreator.new(
          author,
          topic_id: topic.id,
          raw: "Plain post, no whisper targets passed — custom_fields must stay empty.",
        ).create!
      expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
    end

    it "does not interfere with other custom fields set by other plugins" do
      post =
        PostCreator.new(
          author,
          topic_id: topic.id,
          raw: "Post gets a custom field from another plugin in the same create flow.",
        ).create!
      post.custom_fields["some_other_plugin_field"] = "hello"
      post.save_custom_fields
      post.reload
      expect(post.custom_fields["some_other_plugin_field"]).to eq("hello")
      expect(post.custom_fields["whisper_target_user_ids"]).to be_blank
    end
  end

  describe "native staff whisper compatibility" do
    fab!(:native_staff_whisper) do
      Fabricate(:post, topic: topic, user: admin, post_type: Post.types[:whisper])
    end

    it "native staff whispers are unaffected by our plugin (admin still sees)" do
      expect(Guardian.new(admin).can_see_post?(native_staff_whisper)).to eq(true)
    end

    it "native staff whispers remain hidden from non-staff via core's rule" do
      expect(Guardian.new(stranger).can_see_post?(native_staff_whisper)).to eq(false)
    end

    it "our override does not raise when the post has no custom whisper field" do
      expect { Guardian.new(stranger).can_see_post?(native_staff_whisper) }.not_to raise_error
    end
  end

  describe "plugin fully disabled" do
    before { SiteSetting.discourse_whisper_enabled = false }

    it "does not add whisper attributes to the post serializer" do
      whisper = Fabricate(:post, topic: topic, user: author)
      whisper.custom_fields["whisper_target_user_ids"] = [other_user.id]
      whisper.save_custom_fields

      serialized = PostSerializer.new(whisper, scope: Guardian.new(author), root: false).as_json
      expect(serialized).not_to have_key(:is_whisper_to_user)
      expect(serialized).not_to have_key(:whisper_target_user_ids)
      expect(serialized).not_to have_key(:whisper_targets)
    end

    it "does not filter a pre-existing whisper post out of the topic stream" do
      whisper = Fabricate(:post, topic: topic, user: author)
      whisper.custom_fields["whisper_target_user_ids"] = [other_user.id]
      whisper.save_custom_fields

      ids = TopicView.new(topic.id, stranger).posts.map(&:id)
      expect(ids).to include(whisper.id)
    end
  end
end
