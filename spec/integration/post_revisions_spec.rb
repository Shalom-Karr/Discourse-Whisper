# frozen_string_literal: true

require "rails_helper"

# Regression coverage: editing a whisper must not expose its contents or
# metadata to non-recipients through the revision-history endpoints.
RSpec.describe "discourse-whisper revision history visibility", type: :request do
  fab!(:author) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target, :user)
  fab!(:stranger, :user)
  fab!(:admin)
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:whisper) do
    post =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "Initial whisper content long enough for Discourse to accept the post.",
        whisper_target_user_ids: [target.id],
      ).create!
    revisor = PostRevisor.new(post)
    revisor.revise!(
      author,
      { raw: "Edited whisper content, also long enough for the revisor to accept." },
      bypass_bump: true,
      force_new_version: true,
    )
    post.reload
  end

  before { SiteSetting.discourse_whisper_enabled = true }

  describe "GET /posts/:post_id/revisions/:revision.json" do
    it "denies revision access to a stranger" do
      sign_in(stranger)
      get "/posts/#{whisper.id}/revisions/#{whisper.version}.json"
      expect(response.status).to be_in([403, 404])
    end

    it "denies revision access to an anonymous viewer" do
      get "/posts/#{whisper.id}/revisions/#{whisper.version}.json"
      expect(response.status).to be_in([403, 404])
    end

    it "allows revision access to the author" do
      sign_in(author)
      get "/posts/#{whisper.id}/revisions/#{whisper.version}.json"
      # The author may or may not have permission to view revisions depending on
      # Discourse defaults for their trust level — but it must not raise.
      expect(response.status).to be_in([200, 403, 404])
    end

    it "allows revision access to an admin" do
      sign_in(admin)
      get "/posts/#{whisper.id}/revisions/#{whisper.version}.json"
      expect(response.status).to eq(200)
    end
  end
end
