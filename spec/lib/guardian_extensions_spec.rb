# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseWhisper::GuardianExtensions do
  fab!(:author) { Fabricate(:user) }
  fab!(:target) { Fabricate(:user) }
  fab!(:stranger) { Fabricate(:user) }
  fab!(:admin)
  fab!(:moderator)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:whisper_post) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_id"] = target.id
    post.save_custom_fields
    post
  end
  fab!(:normal_post) { Fabricate(:post, topic: topic, user: author) }

  before { SiteSetting.discourse_whisper_enabled = true }

  describe "#can_see_post?" do
    context "when the plugin is disabled" do
      before { SiteSetting.discourse_whisper_enabled = false }

      it "does not hide whisper posts from strangers" do
        expect(Guardian.new(stranger).can_see_post?(whisper_post)).to eq(
          Guardian.new(stranger).can_see_post?(normal_post),
        )
      end
    end

    context "when the post is a whisper" do
      it "allows the author" do
        expect(Guardian.new(author).can_see_post?(whisper_post)).to eq(true)
      end

      it "allows the target user" do
        expect(Guardian.new(target).can_see_post?(whisper_post)).to eq(true)
      end

      it "allows admins" do
        expect(Guardian.new(admin).can_see_post?(whisper_post)).to eq(true)
      end

      it "allows moderators" do
        expect(Guardian.new(moderator).can_see_post?(whisper_post)).to eq(true)
      end

      it "hides the post from an unrelated user" do
        expect(Guardian.new(stranger).can_see_post?(whisper_post)).to eq(false)
      end

      it "hides the post from anonymous viewers" do
        expect(Guardian.new(nil).can_see_post?(whisper_post)).to eq(false)
      end
    end

    context "with a category group moderator" do
      fab!(:cat_mod_group) { Fabricate(:group) }
      fab!(:cat_mod_user) { Fabricate(:user) }

      before do
        cat_mod_group.add(cat_mod_user)
        category.update!(reviewable_by_group_id: cat_mod_group.id)
      end

      it "allows a category group moderator to see the whisper" do
        expect(Guardian.new(cat_mod_user).can_see_post?(whisper_post)).to eq(true)
      end
    end

    context "when the post is NOT a whisper" do
      it "falls through to default Guardian behaviour for strangers" do
        # Baseline: a stranger can see a normal post in a normal category
        expect(Guardian.new(stranger).can_see_post?(normal_post)).to eq(true)
      end
    end

    context "with a malformed or zero whisper target id" do
      it "falls through to default Guardian behaviour" do
        bad_post = Fabricate(:post, topic: topic, user: author)
        bad_post.custom_fields["whisper_target_user_id"] = 0
        bad_post.save_custom_fields
        expect(Guardian.new(stranger).can_see_post?(bad_post)).to eq(true)
      end
    end
  end
end
