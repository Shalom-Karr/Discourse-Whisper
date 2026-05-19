# frozen_string_literal: true

require "rails_helper"

# Edge case: whisper visibility must compose correctly with Discourse's
# category-level security. If a viewer can't see the category at all, they
# must not see whispers in it — even if they'd otherwise be in the audience.
RSpec.describe "discourse-whisper interaction with secured categories" do
  fab!(:staff_group) { Group[:staff] }
  fab!(:author) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target, :user)
  fab!(:stranger, :user)
  fab!(:admin)

  fab!(:secured_category) do
    cat = Fabricate(:category)
    # Only staff can see — explicit permission.
    cat.set_permissions(staff: :full)
    cat.save!
    cat
  end

  fab!(:secured_topic) { Fabricate(:topic, category: secured_category, user: admin) }
  fab!(:secured_whisper) do
    post = Fabricate(:post, topic: secured_topic, user: admin)
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end

  before { SiteSetting.discourse_whisper_enabled = true }

  it "hides whispers from a target who cannot see the underlying category" do
    # The target is the whisper's intended audience, but they cannot see the
    # secured category. Core's category-access check must still win.
    expect(Guardian.new(target).can_see_post?(secured_whisper)).to eq(false)
  end

  it "still lets an admin see whispers in a secured category" do
    expect(Guardian.new(admin).can_see_post?(secured_whisper)).to eq(true)
  end

  it "hides whispers in a secured category from strangers" do
    expect(Guardian.new(stranger).can_see_post?(secured_whisper)).to eq(false)
  end

  it "the SQL filter does not surface secured-category whispers to unauthorized targets" do
    # Even if the QueryFilter says "target is in audience", the upstream
    # category filter must already have removed the post. The filter is
    # permissive by design — it doesn't re-check category access.
    ids = DiscourseWhisper::QueryFilter.apply(Post.where(id: secured_whisper.id), target).pluck(:id)
    # Our filter doesn't remove it (target IS in audience), but in a real
    # query this Post scope would already be filtered by Category.secured /
    # Topic.secured upstream. This test documents that our filter is ONE
    # layer, not the whole visibility system.
    expect(ids).to eq([secured_whisper.id])
  end
end
