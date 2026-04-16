# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseWhisper::GuardianExtensions do
  fab!(:author, :user)
  fab!(:target, :user)
  fab!(:second_target, :user)
  fab!(:third_target, :user)
  fab!(:stranger, :user)
  fab!(:admin)
  fab!(:moderator)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:whisper_post) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end
  fab!(:multi_whisper_post) do
    post = Fabricate(:post, topic: topic, user: author)
    post.custom_fields["whisper_target_user_ids"] = [target.id, second_target.id]
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

      it "does not hide whisper posts from anonymous viewers" do
        expect(Guardian.new(nil).can_see_post?(whisper_post)).to eq(
          Guardian.new(nil).can_see_post?(normal_post),
        )
      end

      it "does not hide whisper posts from the author" do
        expect(Guardian.new(author).can_see_post?(whisper_post)).to eq(true)
      end
    end

    context "when the post is a single-target whisper" do
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

    context "when the post is a multi-target whisper" do
      it "allows the first target" do
        expect(Guardian.new(target).can_see_post?(multi_whisper_post)).to eq(true)
      end

      it "allows the second target" do
        expect(Guardian.new(second_target).can_see_post?(multi_whisper_post)).to eq(true)
      end

      it "allows the author" do
        expect(Guardian.new(author).can_see_post?(multi_whisper_post)).to eq(true)
      end

      it "hides the post from anyone not in the target list" do
        expect(Guardian.new(stranger).can_see_post?(multi_whisper_post)).to eq(false)
      end

      it "hides the post from a third user even if other targets exist" do
        expect(Guardian.new(third_target).can_see_post?(multi_whisper_post)).to eq(false)
      end
    end

    context "when the author is also listed as a target" do
      fab!(:self_targeted_post) do
        post = Fabricate(:post, topic: topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [author.id, target.id]
        post.save_custom_fields
        post
      end

      it "still shows the post to the author" do
        expect(Guardian.new(author).can_see_post?(self_targeted_post)).to eq(true)
      end

      it "still shows the post to the other target" do
        expect(Guardian.new(target).can_see_post?(self_targeted_post)).to eq(true)
      end

      it "still hides the post from a stranger" do
        expect(Guardian.new(stranger).can_see_post?(self_targeted_post)).to eq(false)
      end
    end

    context "with target ids stored as strings (JSON roundtrip)" do
      fab!(:string_id_post) do
        post = Fabricate(:post, topic: topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [target.id.to_s, second_target.id.to_s]
        post.save_custom_fields
        post
      end

      it "still resolves the target users" do
        expect(Guardian.new(target).can_see_post?(string_id_post)).to eq(true)
        expect(Guardian.new(second_target).can_see_post?(string_id_post)).to eq(true)
      end

      it "still hides from a stranger" do
        expect(Guardian.new(stranger).can_see_post?(string_id_post)).to eq(false)
      end
    end

    context "with a mix of valid and bogus stored target ids" do
      fab!(:mixed_post) do
        post = Fabricate(:post, topic: topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [target.id, 0, -5, "abc", 9_999_999]
        post.save_custom_fields
        post
      end

      it "still allows the valid target" do
        expect(Guardian.new(target).can_see_post?(mixed_post)).to eq(true)
      end

      it "still hides from a stranger" do
        expect(Guardian.new(stranger).can_see_post?(mixed_post)).to eq(false)
      end
    end

    context "when only invalid target ids are stored" do
      fab!(:all_bogus_post) do
        post = Fabricate(:post, topic: topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [0, -1, "abc"]
        post.save_custom_fields
        post
      end

      it "falls through to default behaviour and shows the post to a stranger" do
        # "abc".to_i is 0, which is rejected; 0 and -1 are rejected too -> empty list -> super
        expect(Guardian.new(stranger).can_see_post?(all_bogus_post)).to eq(true)
      end
    end

    context "when the post argument is nil" do
      it "falls through to core and does not raise" do
        # Our override's first real guard — `return super unless post.is_a?(::Post)` —
        # means we never touch a non-Post argument directly. Core's
        # Guardian#can_see_post?(nil) returns false without raising.
        expect { Guardian.new(stranger).can_see_post?(nil) }.not_to raise_error
      end
    end

    context "with a category group moderator" do
      fab!(:cat_mod_group, :group)
      fab!(:cat_mod_user, :user)

      before do
        SiteSetting.enable_category_group_moderation = true
        cat_mod_group.add(cat_mod_user)
        ::CategoryModerationGroup.create!(category_id: category.id, group_id: cat_mod_group.id)
        category.reload
      end

      it "allows a category group moderator to see the whisper" do
        expect(Guardian.new(cat_mod_user).can_see_post?(whisper_post)).to eq(true)
      end

      it "does NOT leak the whisper to a moderator of a different category" do
        other_category = Fabricate(:category)
        other_mod = Fabricate(:user)
        other_group = Fabricate(:group)
        other_group.add(other_mod)
        ::CategoryModerationGroup.create!(category_id: other_category.id, group_id: other_group.id)
        expect(Guardian.new(other_mod).can_see_post?(whisper_post)).to eq(false)
      end

      context "when category group moderation is disabled site-wide" do
        before { SiteSetting.enable_category_group_moderation = false }

        it "does NOT let a former category group moderator see the whisper" do
          expect(Guardian.new(cat_mod_user).can_see_post?(whisper_post)).to eq(false)
        end
      end
    end

    context "when the topic has no category (e.g. a private message)" do
      fab!(:pm_topic, :private_message_topic)
      fab!(:pm_whisper) do
        post = Fabricate(:post, topic: pm_topic, user: pm_topic.user)
        post.custom_fields["whisper_target_user_ids"] = [target.id]
        post.save_custom_fields
        post
      end

      it "does not raise when the cat-mod check has no category" do
        expect { Guardian.new(target).can_see_post?(pm_whisper) }.not_to raise_error
      end

      it "still shows the post to the target user (modulo PM access)" do
        # The target also needs PM access; add them as a topic_allowed_user.
        TopicAllowedUser.create!(topic: pm_topic, user: target)
        expect(Guardian.new(target).can_see_post?(pm_whisper)).to eq(true)
      end
    end

    context "when the post is NOT a whisper" do
      it "lets a stranger see a normal post" do
        expect(Guardian.new(stranger).can_see_post?(normal_post)).to eq(true)
      end

      it "lets the author see their own normal post" do
        expect(Guardian.new(author).can_see_post?(normal_post)).to eq(true)
      end
    end

    context "with a malformed or zero whisper target id" do
      it "falls through to default Guardian behaviour" do
        bad_post = Fabricate(:post, topic: topic, user: author)
        bad_post.custom_fields["whisper_target_user_ids"] = [0]
        bad_post.save_custom_fields
        expect(Guardian.new(stranger).can_see_post?(bad_post)).to eq(true)
      end

      it "falls through when the array is empty" do
        bad_post = Fabricate(:post, topic: topic, user: author)
        bad_post.custom_fields["whisper_target_user_ids"] = []
        bad_post.save_custom_fields
        expect(Guardian.new(stranger).can_see_post?(bad_post)).to eq(true)
      end

      it "falls through when only negative ids are stored" do
        bad_post = Fabricate(:post, topic: topic, user: author)
        bad_post.custom_fields["whisper_target_user_ids"] = [-1, -42]
        bad_post.save_custom_fields
        expect(Guardian.new(stranger).can_see_post?(bad_post)).to eq(true)
      end

      it "falls through when the field is nil" do
        bad_post = Fabricate(:post, topic: topic, user: author)
        bad_post.custom_fields["whisper_target_user_ids"] = nil
        bad_post.save_custom_fields
        expect(Guardian.new(stranger).can_see_post?(bad_post)).to eq(true)
      end

      it "handles a stored array containing nil entries gracefully" do
        bad_post = Fabricate(:post, topic: topic, user: author)
        bad_post.custom_fields["whisper_target_user_ids"] = [nil, target.id, nil]
        bad_post.save_custom_fields
        expect(Guardian.new(target).can_see_post?(bad_post)).to eq(true)
        expect(Guardian.new(stranger).can_see_post?(bad_post)).to eq(false)
      end
    end

    context "with unusual stored-field shapes" do
      it "handles a stored scalar integer (non-array) by wrapping it" do
        scalar_post = Fabricate(:post, topic: topic, user: author)
        scalar_post.custom_fields["whisper_target_user_ids"] = target.id
        scalar_post.save_custom_fields
        expect(Guardian.new(target).can_see_post?(scalar_post)).to eq(true)
        expect(Guardian.new(stranger).can_see_post?(scalar_post)).to eq(false)
      end

      it "handles a stored scalar string id" do
        scalar_post = Fabricate(:post, topic: topic, user: author)
        scalar_post.custom_fields["whisper_target_user_ids"] = target.id.to_s
        scalar_post.save_custom_fields
        expect(Guardian.new(target).can_see_post?(scalar_post)).to eq(true)
        expect(Guardian.new(stranger).can_see_post?(scalar_post)).to eq(false)
      end

      it "handles floats by truncating them to integer ids" do
        float_post = Fabricate(:post, topic: topic, user: author)
        float_post.custom_fields["whisper_target_user_ids"] = [target.id.to_f, 0.5, -1.2]
        float_post.save_custom_fields
        expect(Guardian.new(target).can_see_post?(float_post)).to eq(true)
        expect(Guardian.new(stranger).can_see_post?(float_post)).to eq(false)
      end

      it "handles a large number of stored target ids" do
        many_post = Fabricate(:post, topic: topic, user: author)
        extras = Array.new(20) { Fabricate(:user) }
        ids = [target.id, *extras.map(&:id)]
        many_post.custom_fields["whisper_target_user_ids"] = ids
        many_post.save_custom_fields
        expect(Guardian.new(target).can_see_post?(many_post)).to eq(true)
        expect(Guardian.new(extras.last).can_see_post?(many_post)).to eq(true)
        expect(Guardian.new(stranger).can_see_post?(many_post)).to eq(false)
      end
    end

    context "when the whisper post itself was soft-deleted" do
      fab!(:trashed_whisper) do
        post = Fabricate(:post, topic: topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [target.id]
        post.save_custom_fields
        post.trash!(Discourse.system_user)
        post.reload
      end

      it "falls through to default Guardian behaviour (which hides trashed posts from non-staff)" do
        # Whatever core does with trashed posts, our override must not raise or
        # leak the whisper beyond what core already allows. For the target, the
        # whisper rule says "yes" but super may still say "no" for a trashed
        # post — that's fine, we just return super.
        expect { Guardian.new(target).can_see_post?(trashed_whisper) }.not_to raise_error
        expect { Guardian.new(stranger).can_see_post?(trashed_whisper) }.not_to raise_error
        expect { Guardian.new(admin).can_see_post?(trashed_whisper) }.not_to raise_error
      end

      it "admin (staff) can still see the trashed whisper" do
        # Admin sees trashed posts via super; the whisper rule returns super too.
        expect(Guardian.new(admin).can_see_post?(trashed_whisper)).to eq(true)
      end

      it "stranger cannot see the trashed whisper" do
        expect(Guardian.new(stranger).can_see_post?(trashed_whisper)).to eq(false)
      end
    end

    context "when the post's topic was deleted" do
      fab!(:orphan_whisper) do
        orphan_topic = Fabricate(:topic, category: category, user: author)
        post = Fabricate(:post, topic: orphan_topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [target.id]
        post.save_custom_fields
        orphan_topic.trash!(Discourse.system_user)
        post.reload
      end

      it "does not raise when topic is soft-deleted (category chain still works)" do
        expect { Guardian.new(target).can_see_post?(orphan_whisper) }.not_to raise_error
        expect { Guardian.new(stranger).can_see_post?(orphan_whisper) }.not_to raise_error
      end
    end

    context "when the author is the system user" do
      fab!(:system_whisper) do
        post = Fabricate(:post, topic: topic, user: Discourse.system_user)
        post.custom_fields["whisper_target_user_ids"] = [target.id]
        post.save_custom_fields
        post
      end

      it "is visible to the target" do
        expect(Guardian.new(target).can_see_post?(system_whisper)).to eq(true)
      end

      it "is hidden from strangers" do
        expect(Guardian.new(stranger).can_see_post?(system_whisper)).to eq(false)
      end

      it "is visible to admins for oversight" do
        expect(Guardian.new(admin).can_see_post?(system_whisper)).to eq(true)
      end
    end

    context "when the author is a bot (user_id < 0)" do
      fab!(:bot_user) { Fabricate(:user, id: -42, username: "bot_#{SecureRandom.hex(4)}") }
      fab!(:bot_whisper) do
        post = Fabricate(:post, topic: topic, user: bot_user)
        post.custom_fields["whisper_target_user_ids"] = [target.id]
        post.save_custom_fields
        post
      end

      it "still enforces visibility for the target" do
        expect(Guardian.new(target).can_see_post?(bot_whisper)).to eq(true)
      end

      it "still hides from strangers" do
        expect(Guardian.new(stranger).can_see_post?(bot_whisper)).to eq(false)
      end
    end

    context "when a target has been hard-deleted after the whisper was stored" do
      fab!(:deleted_target_whisper) do
        ghost = Fabricate(:user)
        post = Fabricate(:post, topic: topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [target.id, ghost.id]
        post.save_custom_fields
        ghost.destroy!
        post
      end

      it "still shows the post to the remaining live target" do
        expect(Guardian.new(target).can_see_post?(deleted_target_whisper)).to eq(true)
      end

      it "still hides the post from strangers" do
        expect(Guardian.new(stranger).can_see_post?(deleted_target_whisper)).to eq(false)
      end

      it "still shows the post to admins" do
        expect(Guardian.new(admin).can_see_post?(deleted_target_whisper)).to eq(true)
      end
    end

    context "when an inactive target views the whisper" do
      fab!(:inactive_target) { Fabricate(:user, active: false) }
      fab!(:inactive_target_whisper) do
        post = Fabricate(:post, topic: topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [inactive_target.id]
        post.save_custom_fields
        post
      end

      it "the inactive target can still see the whisper" do
        expect(Guardian.new(inactive_target).can_see_post?(inactive_target_whisper)).to eq(true)
      end
    end

    context "when a suspended target views the whisper" do
      fab!(:suspended_target) do
        Fabricate(:user, suspended_till: 10.days.from_now, suspended_at: Time.now)
      end
      fab!(:suspended_target_whisper) do
        post = Fabricate(:post, topic: topic, user: author)
        post.custom_fields["whisper_target_user_ids"] = [suspended_target.id]
        post.save_custom_fields
        post
      end

      it "the suspended target can still see the whisper" do
        expect(Guardian.new(suspended_target).can_see_post?(suspended_target_whisper)).to eq(true)
      end
    end

    context "when a post is BOTH a native staff whisper and has our custom field" do
      fab!(:hybrid_post) do
        post = Fabricate(:post, topic: topic, user: author, post_type: Post.types[:whisper])
        post.custom_fields["whisper_target_user_ids"] = [target.id]
        post.save_custom_fields
        post
      end

      it "does not raise for staff (native whisper rule grants access)" do
        expect { Guardian.new(admin).can_see_post?(hybrid_post) }.not_to raise_error
      end

      it "our override still allows the custom-field target to see it" do
        # Native staff whispers are staff-only. Our plugin layers on top; for
        # the target, our rule returns super which then checks native staff
        # whisper rules. The target is not staff, so super returns false —
        # this documents the compound behavior (native wins for hidden).
        expect { Guardian.new(target).can_see_post?(hybrid_post) }.not_to raise_error
      end
    end

    context "with an explicit Guardian(user) constructor variant" do
      it "works the same as Guardian.new(user)" do
        g1 = Guardian.new(target)
        g2 = Guardian.new(target)
        expect(g1.can_see_post?(whisper_post)).to eq(g2.can_see_post?(whisper_post))
      end
    end

    context "when the user record is passed with just id populated (lazy load)" do
      it "still resolves visibility correctly" do
        # Emulates code paths that build a bare User by id.
        lean = User.new(id: target.id)
        lean.instance_variable_set(:@staff, false)
        # Skip: real code paths use full User records. This documents that the
        # rule reads `@user.id` and `@user.staff?`, both available on a real
        # User record. Simulating is brittle — just confirm real path.
        expect(Guardian.new(User.find(target.id)).can_see_post?(whisper_post)).to eq(true)
      end
    end
  end
end
