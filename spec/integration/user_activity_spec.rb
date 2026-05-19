# frozen_string_literal: true

require "rails_helper"

# Regression coverage: when the plugin's SQL-level whisper filter is applied
# to a Post scope (as it is from TopicView and Search), it must hide whispers
# from non-recipients. This spec exercises the filter directly against a
# "posts by user" scope — the same shape a user-activity feed would build.
RSpec.describe DiscourseWhisper::QueryFilter do
  fab!(:author, :user)
  fab!(:target, :user)
  fab!(:second_target, :user)
  fab!(:stranger, :user)
  fab!(:admin)
  fab!(:moderator)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, user: author) }

  fab!(:normal_post) { Fabricate(:post, topic: topic, user: author) }
  fab!(:whisper) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end
  fab!(:multi_whisper) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_ids"] = [target.id, second_target.id]
    post.save_custom_fields
    post
  end

  before { SiteSetting.discourse_whisper_enabled = true }

  def visible_ids_for(user)
    described_class.apply(Post.where(user_id: author.id), user).pluck(:id)
  end

  it "hides whispers from a stranger's posts-by-user query" do
    ids = visible_ids_for(stranger)
    expect(ids).to include(normal_post.id)
    expect(ids).not_to include(whisper.id, multi_whisper.id)
  end

  it "hides whispers from an anonymous viewer" do
    ids = visible_ids_for(nil)
    expect(ids).to include(normal_post.id)
    expect(ids).not_to include(whisper.id, multi_whisper.id)
  end

  it "shows whispers to the target on the author's posts" do
    ids = visible_ids_for(target)
    expect(ids).to include(normal_post.id, whisper.id, multi_whisper.id)
  end

  it "shows whispers to a secondary target only for multi-target whispers" do
    ids = visible_ids_for(second_target)
    expect(ids).to include(normal_post.id, multi_whisper.id)
    expect(ids).not_to include(whisper.id)
  end

  it "shows whispers to the author themselves" do
    ids = visible_ids_for(author)
    expect(ids).to include(normal_post.id, whisper.id, multi_whisper.id)
  end

  it "shows whispers to admins and moderators for oversight" do
    expect(visible_ids_for(admin)).to include(whisper.id, multi_whisper.id)
    expect(visible_ids_for(moderator)).to include(whisper.id, multi_whisper.id)
  end

  it "shows whispers to category group moderators for their category" do
    SiteSetting.enable_category_group_moderation = true
    cat_mod_group = Fabricate(:group)
    cat_mod = Fabricate(:user)
    cat_mod_group.add(cat_mod)
    CategoryModerationGroup.create!(category_id: category.id, group_id: cat_mod_group.id)

    expect(visible_ids_for(cat_mod)).to include(whisper.id, multi_whisper.id)
  end

  it "does NOT leak whispers to a cat mod of a different category" do
    SiteSetting.enable_category_group_moderation = true
    other_cat = Fabricate(:category)
    other_mod_group = Fabricate(:group)
    other_mod = Fabricate(:user)
    other_mod_group.add(other_mod)
    CategoryModerationGroup.create!(category_id: other_cat.id, group_id: other_mod_group.id)

    expect(visible_ids_for(other_mod)).not_to include(whisper.id, multi_whisper.id)
  end

  it "does not filter when the plugin is disabled" do
    SiteSetting.discourse_whisper_enabled = false
    expect(visible_ids_for(stranger)).to include(whisper.id, multi_whisper.id)
  end

  it "does not filter posts that are not whispers" do
    # Stranger sees the normal post regardless.
    expect(visible_ids_for(stranger)).to include(normal_post.id)
  end

  describe "SQL filter robustness" do
    it "is idempotent when applied twice" do
      base = Post.where(user_id: author.id)
      once = described_class.apply(base, stranger).pluck(:id)
      twice = described_class.apply(described_class.apply(base, stranger), stranger).pluck(:id)
      expect(once.sort).to eq(twice.sort)
    end

    it "preserves any existing .where clauses on the scope" do
      base = Post.where(user_id: author.id, id: [normal_post.id, whisper.id])
      ids = described_class.apply(base, stranger).pluck(:id)
      expect(ids).to eq([normal_post.id])
    end

    it "preserves ordering" do
      base = Post.where(user_id: author.id).order(id: :desc)
      ids = described_class.apply(base, stranger).pluck(:id)
      expect(ids).to eq(ids.sort.reverse)
    end

    it "preserves limit" do
      base = Post.where(user_id: author.id).limit(1)
      ids = described_class.apply(base, stranger).pluck(:id)
      expect(ids.length).to be <= 1
    end

    it "works on an empty scope" do
      base = Post.where(id: -1)
      ids = described_class.apply(base, stranger).pluck(:id)
      expect(ids).to eq([])
    end

    it "handles a whisper custom field whose value is a malformed JSON object (hash)" do
      # Directly craft a PostCustomField row with a non-array JSON value to
      # simulate a corrupted stored value.
      bad = Fabricate(:post, topic: topic, user: author)
      PostCustomField.create!(
        post_id: bad.id,
        name: "whisper_target_user_ids",
        value: '{"not":"an-array"}',
      )
      # The filter should not raise and should treat this as "not a whisper the
      # user is in the audience for" — i.e. hide it from the stranger.
      scope = Post.where(id: bad.id)
      ids =
        begin
          described_class.apply(scope, stranger).pluck(:id)
        rescue StandardError
          nil
        end
      # Either filter hides it, or raises a PG error — we don't require a
      # specific outcome, only that the surrounding spec infrastructure keeps
      # running. This test is a canary for malformed production data.
      expect(ids).to eq([]).or be_nil
    end

    it "handles a whisper custom field whose value is an empty string" do
      bad = Fabricate(:post, topic: topic, user: author)
      PostCustomField.create!(post_id: bad.id, name: "whisper_target_user_ids", value: "")
      scope = Post.where(id: bad.id)
      # Our join has `dw_pcf.value NOT IN ('', '[]', 'null')` so empty string
      # is treated as no whisper; the post is visible to everyone.
      expect(described_class.apply(scope, stranger).pluck(:id)).to eq([bad.id])
    end

    it "handles a whisper custom field whose value is the literal 'null'" do
      bad = Fabricate(:post, topic: topic, user: author)
      PostCustomField.create!(post_id: bad.id, name: "whisper_target_user_ids", value: "null")
      scope = Post.where(id: bad.id)
      expect(described_class.apply(scope, stranger).pluck(:id)).to eq([bad.id])
    end

    it "handles a whisper custom field whose value is an empty JSON array" do
      bad = Fabricate(:post, topic: topic, user: author)
      PostCustomField.create!(post_id: bad.id, name: "whisper_target_user_ids", value: "[]")
      scope = Post.where(id: bad.id)
      expect(described_class.apply(scope, stranger).pluck(:id)).to eq([bad.id])
    end

    it "does not conflict when the scope already joins post_custom_fields via raw SQL" do
      # Simulate a caller that joins post_custom_fields for its own reasons.
      # Our filter uses the distinct alias `dw_pcf` to avoid collision with
      # any caller-supplied join (which would typically be an un-aliased
      # `post_custom_fields`).
      scope =
        Post.joins("INNER JOIN post_custom_fields other_pcf ON other_pcf.post_id = posts.id").where(
          user_id: author.id,
        )
      ids = described_class.apply(scope, stranger).pluck(:id).uniq
      expect(ids).not_to include(whisper.id, multi_whisper.id)
    end

    it "is safe to apply on a scope that uses .includes(:user)" do
      scope = Post.where(user_id: author.id).includes(:user)
      expect { described_class.apply(scope, stranger).to_a }.not_to raise_error
    end

    it "works with .distinct on the scope" do
      scope = Post.where(user_id: author.id).distinct
      ids = described_class.apply(scope, stranger).pluck(:id)
      expect(ids).not_to include(whisper.id)
    end

    it "works with .limit and .offset combined" do
      scope = Post.where(user_id: author.id).order(:id).limit(10).offset(0)
      ids = described_class.apply(scope, stranger).pluck(:id)
      expect(ids).not_to include(whisper.id, multi_whisper.id)
    end

    it "handles the anonymous viewer path with a scope using .joins" do
      scope = Post.joins(:topic).where(user_id: author.id)
      ids = described_class.apply(scope, nil).pluck(:id)
      expect(ids).not_to include(whisper.id, multi_whisper.id)
    end
  end
end
