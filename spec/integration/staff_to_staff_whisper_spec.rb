# frozen_string_literal: true

require "rails_helper"

# Behavior rule: category group moderators have oversight over whispers that
# include at least one non-staff participant. A whisper where the author AND
# every target are site staff (admin or moderator) is treated as a staff-only
# conversation — category group moderators must NOT see it. Site-wide staff
# (admins + moderators) still see everything for true oversight.
RSpec.describe "discourse-whisper staff-to-staff whisper visibility" do
  fab!(:admin_author, :admin)
  fab!(:admin_target, :admin)
  fab!(:moderator_target, :moderator)
  fab!(:regular_user, :user)
  fab!(:stranger, :user)
  fab!(:site_admin, :admin)
  fab!(:site_moderator, :moderator)

  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, user: admin_author) }

  fab!(:cat_mod_group, :group)
  fab!(:cat_mod_user, :user)

  before do
    SiteSetting.discourse_whisper_enabled = true
    SiteSetting.enable_category_group_moderation = true
    cat_mod_group.add(cat_mod_user)
    CategoryModerationGroup.create!(category_id: category.id, group_id: cat_mod_group.id)
    category.reload
  end

  # ----- Guardian per-post rule -----

  describe "Guardian#can_see_post?" do
    context "when an admin whispers an admin" do
      fab!(:post_a2a) do
        post = Fabricate(:post, topic: topic, user: admin_author)
        post.custom_fields["whisper_target_user_ids"] = [admin_target.id]
        post.save_custom_fields
        post
      end

      it "IS visible to the admin author" do
        expect(Guardian.new(admin_author).can_see_post?(post_a2a)).to eq(true)
      end

      it "IS visible to the admin target" do
        expect(Guardian.new(admin_target).can_see_post?(post_a2a)).to eq(true)
      end

      it "IS visible to a site admin (full oversight)" do
        expect(Guardian.new(site_admin).can_see_post?(post_a2a)).to eq(true)
      end

      it "IS visible to a site moderator (full oversight)" do
        expect(Guardian.new(site_moderator).can_see_post?(post_a2a)).to eq(true)
      end

      it "is NOT visible to a category group moderator (no staff-on-staff oversight)" do
        expect(Guardian.new(cat_mod_user).can_see_post?(post_a2a)).to eq(false)
      end

      it "is NOT visible to a stranger" do
        expect(Guardian.new(stranger).can_see_post?(post_a2a)).to eq(false)
      end

      it "is NOT visible to anon" do
        expect(Guardian.new(nil).can_see_post?(post_a2a)).to eq(false)
      end
    end

    context "when an admin whispers a moderator" do
      fab!(:post_a2m) do
        post = Fabricate(:post, topic: topic, user: admin_author)
        post.custom_fields["whisper_target_user_ids"] = [moderator_target.id]
        post.save_custom_fields
        post
      end

      it "is NOT visible to a category group moderator (admin + mod are both staff)" do
        expect(Guardian.new(cat_mod_user).can_see_post?(post_a2m)).to eq(false)
      end

      it "IS visible to the moderator target" do
        expect(Guardian.new(moderator_target).can_see_post?(post_a2m)).to eq(true)
      end
    end

    context "when an admin whispers a mix of admin and regular user" do
      fab!(:post_mixed) do
        post = Fabricate(:post, topic: topic, user: admin_author)
        post.custom_fields["whisper_target_user_ids"] = [admin_target.id, regular_user.id]
        post.save_custom_fields
        post
      end

      it "IS visible to a category group moderator (non-staff participant present)" do
        expect(Guardian.new(cat_mod_user).can_see_post?(post_mixed)).to eq(true)
      end
    end

    context "when a regular user whispers an admin" do
      fab!(:post_u2a) do
        post = Fabricate(:post, topic: topic, user: regular_user)
        post.custom_fields["whisper_target_user_ids"] = [admin_target.id]
        post.save_custom_fields
        post
      end

      it "IS visible to a category group moderator (author is non-staff)" do
        expect(Guardian.new(cat_mod_user).can_see_post?(post_u2a)).to eq(true)
      end
    end

    context "when a moderator whispers a moderator (also all-staff)" do
      fab!(:post_m2m) do
        post = Fabricate(:post, topic: topic, user: site_moderator)
        post.custom_fields["whisper_target_user_ids"] = [moderator_target.id]
        post.save_custom_fields
        post
      end

      it "is NOT visible to a category group moderator" do
        expect(Guardian.new(cat_mod_user).can_see_post?(post_m2m)).to eq(false)
      end
    end

    context "when an admin whispers multiple admins" do
      fab!(:extra_admin, :admin)
      fab!(:post_multi_a) do
        post = Fabricate(:post, topic: topic, user: admin_author)
        post.custom_fields["whisper_target_user_ids"] = [admin_target.id, extra_admin.id]
        post.save_custom_fields
        post
      end

      it "is NOT visible to a category group moderator" do
        expect(Guardian.new(cat_mod_user).can_see_post?(post_multi_a)).to eq(false)
      end

      it "IS visible to each admin target" do
        expect(Guardian.new(admin_target).can_see_post?(post_multi_a)).to eq(true)
        expect(Guardian.new(extra_admin).can_see_post?(post_multi_a)).to eq(true)
      end
    end

    context "when some target IDs reference deleted users in an admin whisper" do
      fab!(:post_with_ghost) do
        ghost = Fabricate(:user)
        post = Fabricate(:post, topic: topic, user: admin_author)
        post.custom_fields["whisper_target_user_ids"] = [admin_target.id, ghost.id]
        post.save_custom_fields
        ghost.destroy!
        post
      end

      it "is NOT visible to a category group moderator when the live targets are all staff" do
        # The deleted (non-staff) user no longer exists, so SQL's EXISTS on
        # non-staff targets returns false. Only live staff remain → cat mod
        # is excluded.
        expect(Guardian.new(cat_mod_user).can_see_post?(post_with_ghost)).to eq(false)
      end
    end
  end

  # ----- SQL-level QueryFilter -----

  describe "DiscourseWhisper::QueryFilter" do
    fab!(:a2a_post) do
      post = Fabricate(:post, topic: topic, user: admin_author)
      post.custom_fields["whisper_target_user_ids"] = [admin_target.id]
      post.save_custom_fields
      post
    end
    fab!(:mixed_post) do
      post = Fabricate(:post, topic: topic, user: admin_author)
      post.custom_fields["whisper_target_user_ids"] = [admin_target.id, regular_user.id]
      post.save_custom_fields
      post
    end

    def visible_ids_for(user)
      DiscourseWhisper::QueryFilter.apply(Post.where(user_id: admin_author.id), user).pluck(:id)
    end

    it "excludes staff-to-staff whispers from a category group moderator's view" do
      expect(visible_ids_for(cat_mod_user)).not_to include(a2a_post.id)
    end

    it "includes mixed-audience whispers in a category group moderator's view" do
      expect(visible_ids_for(cat_mod_user)).to include(mixed_post.id)
    end

    it "still includes staff-to-staff whispers for site admins" do
      expect(visible_ids_for(site_admin)).to include(a2a_post.id)
    end

    it "still includes staff-to-staff whispers for the admin author" do
      expect(visible_ids_for(admin_author)).to include(a2a_post.id)
    end

    it "still includes staff-to-staff whispers for the admin target" do
      expect(visible_ids_for(admin_target)).to include(a2a_post.id)
    end
  end

  # ----- DiscourseWhisper.staff_to_staff? helper -----

  describe ".staff_to_staff?" do
    it "returns true when admin whispers admin" do
      post = Fabricate(:post, user: admin_author)
      expect(DiscourseWhisper.staff_to_staff?(post, [admin_target.id])).to eq(true)
    end

    it "returns false when author is not staff" do
      post = Fabricate(:post, user: regular_user)
      expect(DiscourseWhisper.staff_to_staff?(post, [admin_target.id])).to eq(false)
    end

    it "returns false when any single target is not staff" do
      post = Fabricate(:post, user: admin_author)
      expect(DiscourseWhisper.staff_to_staff?(post, [admin_target.id, regular_user.id])).to eq(
        false,
      )
    end

    it "returns false when target_ids is empty" do
      post = Fabricate(:post, user: admin_author)
      expect(DiscourseWhisper.staff_to_staff?(post, [])).to eq(false)
    end

    it "returns true for admin → moderator (both staff)" do
      post = Fabricate(:post, user: admin_author)
      expect(DiscourseWhisper.staff_to_staff?(post, [moderator_target.id])).to eq(true)
    end

    it "returns true for moderator → admin" do
      post = Fabricate(:post, user: site_moderator)
      expect(DiscourseWhisper.staff_to_staff?(post, [admin_target.id])).to eq(true)
    end
  end
end
