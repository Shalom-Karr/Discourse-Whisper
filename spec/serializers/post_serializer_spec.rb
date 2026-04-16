# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "discourse-whisper PostSerializer additions" do
  fab!(:author, :user)
  fab!(:target, :user)
  fab!(:second_target, :user)
  fab!(:topic)
  fab!(:whisper_post) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_ids"] = [target.id, second_target.id]
    post.save_custom_fields
    post
  end
  fab!(:single_whisper_post) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end
  fab!(:normal_post) { Fabricate(:post, topic: topic, user: author) }

  before { SiteSetting.discourse_whisper_enabled = true }

  def serialize(post, viewer)
    PostSerializer.new(post, scope: Guardian.new(viewer), root: false).as_json
  end

  describe "is_whisper_to_user" do
    it "is true for a whisper post" do
      expect(serialize(whisper_post, author)[:is_whisper_to_user]).to eq(true)
    end

    it "is false for a normal post" do
      expect(serialize(normal_post, author)[:is_whisper_to_user]).to eq(false)
    end

    it "is omitted entirely when the plugin is disabled" do
      SiteSetting.discourse_whisper_enabled = false
      expect(serialize(whisper_post, author)).not_to have_key(:is_whisper_to_user)
    end

    it "is included for any viewer who can see the post (author)" do
      expect(serialize(whisper_post, author)).to have_key(:is_whisper_to_user)
    end
  end

  describe "whisper_target_user_ids" do
    it "returns the array of recipient ids as integers" do
      result = serialize(whisper_post, author)
      expect(result[:whisper_target_user_ids]).to contain_exactly(target.id, second_target.id)
      result[:whisper_target_user_ids].each { |id| expect(id).to be_a(Integer) }
    end

    it "returns a single-element array for a single-target whisper" do
      result = serialize(single_whisper_post, author)
      expect(result[:whisper_target_user_ids]).to eq([target.id])
    end

    it "is omitted when the post is not a whisper" do
      expect(serialize(normal_post, author)).not_to have_key(:whisper_target_user_ids)
    end

    it "is omitted when the plugin is disabled" do
      SiteSetting.discourse_whisper_enabled = false
      expect(serialize(whisper_post, author)).not_to have_key(:whisper_target_user_ids)
    end

    it "coerces stored string ids to integers" do
      post = Fabricate(:post, topic: topic, user: author)
      post.custom_fields["whisper_target_user_ids"] = [target.id.to_s]
      post.save_custom_fields
      result = serialize(post, author)
      expect(result[:whisper_target_user_ids]).to eq([target.id])
    end
  end

  describe "whisper_targets" do
    it "returns id, username and avatar_template for each recipient" do
      targets = serialize(whisper_post, author)[:whisper_targets]
      expect(targets.length).to eq(2)

      target_entry = targets.find { |t| t[:id] == target.id }
      expect(target_entry[:username]).to eq(target.username)
      expect(target_entry[:avatar_template]).to eq(target.avatar_template)

      second_entry = targets.find { |t| t[:id] == second_target.id }
      expect(second_entry[:username]).to eq(second_target.username)
      expect(second_entry[:avatar_template]).to eq(second_target.avatar_template)
    end

    it "silently drops recipients whose user records have been deleted" do
      gone = Fabricate(:user)
      post = Fabricate(:post, topic: topic, user: author)
      post.custom_fields["whisper_target_user_ids"] = [target.id, gone.id]
      post.save_custom_fields
      gone.destroy!

      result = serialize(post, author)
      expect(result[:whisper_targets].map { |t| t[:id] }).to contain_exactly(target.id)
    end

    it "still includes the deleted user's id in whisper_target_user_ids (custom field is not pruned)" do
      gone = Fabricate(:user)
      post = Fabricate(:post, topic: topic, user: author)
      post.custom_fields["whisper_target_user_ids"] = [target.id, gone.id]
      post.save_custom_fields
      gone_id = gone.id
      gone.destroy!

      result = serialize(post, author)
      expect(result[:whisper_target_user_ids]).to contain_exactly(target.id, gone_id)
    end

    it "is omitted when the plugin is disabled" do
      SiteSetting.discourse_whisper_enabled = false
      expect(serialize(whisper_post, author)).not_to have_key(:whisper_targets)
    end

    it "is omitted on a normal post" do
      expect(serialize(normal_post, author)).not_to have_key(:whisper_targets)
    end

    it "is empty-array shape if all recipients were deleted" do
      gone1 = Fabricate(:user)
      gone2 = Fabricate(:user)
      post = Fabricate(:post, topic: topic, user: author)
      post.custom_fields["whisper_target_user_ids"] = [gone1.id, gone2.id]
      post.save_custom_fields
      gone1.destroy!
      gone2.destroy!

      result = serialize(post, author)
      expect(result[:whisper_targets]).to eq([])
    end

    it "is consistent when viewed by the target" do
      result = serialize(whisper_post, target)
      targets = result[:whisper_targets]
      expect(targets.map { |t| t[:id] }).to contain_exactly(target.id, second_target.id)
    end

    it "is consistent when viewed by an admin" do
      admin = Fabricate(:admin)
      result = serialize(whisper_post, admin)
      targets = result[:whisper_targets]
      expect(targets.map { |t| t[:id] }).to contain_exactly(target.id, second_target.id)
    end

    it "handles a very large audience efficiently" do
      extras = Array.new(25) { Fabricate(:user) }
      post = Fabricate(:post, topic: topic, user: author)
      post.custom_fields["whisper_target_user_ids"] = extras.map(&:id)
      post.save_custom_fields

      result = serialize(post, author)
      expect(result[:whisper_targets].length).to eq(25)
      expect(result[:whisper_target_user_ids].length).to eq(25)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
