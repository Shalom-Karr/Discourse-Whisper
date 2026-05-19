# frozen_string_literal: true

require "rails_helper"

# Regression coverage: the Posts API endpoints must respect the whisper
# visibility rule. A direct GET on a whisper post's JSON must be denied for
# strangers and anonymous viewers, and allowed for recipients / staff.
RSpec.describe "discourse-whisper Posts API visibility", type: :request do
  fab!(:author, :user)
  fab!(:target, :user)
  fab!(:stranger, :user)
  fab!(:admin)
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:whisper) do
    post =
      Fabricate(
        :post,
        topic: topic,
        user: author,
        raw: "Whisper API visibility test content here, plenty of text.",
      )
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end

  before { SiteSetting.discourse_whisper_enabled = true }

  describe "GET /posts/:id.json" do
    it "is denied for a stranger" do
      sign_in(stranger)
      get "/posts/#{whisper.id}.json"
      expect(response.status).to be_in([403, 404])
    end

    it "is denied for an anonymous viewer" do
      get "/posts/#{whisper.id}.json"
      expect(response.status).to be_in([403, 404])
    end

    it "is allowed for the author" do
      sign_in(author)
      get "/posts/#{whisper.id}.json"
      expect(response.status).to eq(200)
    end

    it "is allowed for a target recipient" do
      sign_in(target)
      get "/posts/#{whisper.id}.json"
      expect(response.status).to eq(200)
    end

    it "is allowed for an admin" do
      sign_in(admin)
      get "/posts/#{whisper.id}.json"
      expect(response.status).to eq(200)
    end

    it "returns the whisper metadata to an authorized viewer" do
      sign_in(author)
      get "/posts/#{whisper.id}.json"
      body = response.parsed_body
      expect(body["is_whisper_to_user"]).to eq(true)
      expect(body["whisper_target_user_ids"]).to contain_exactly(target.id)
      expect(body["whisper_targets"].map { |t| t["id"] }).to contain_exactly(target.id)
    end
  end

  describe "GET /t/:slug/:id.json (topic stream)" do
    let!(:other_post) { Fabricate(:post, topic: topic, user: author) }

    it "excludes the whisper from a stranger's topic JSON" do
      sign_in(stranger)
      get "/t/#{topic.id}.json"
      ids = response.parsed_body["post_stream"]["posts"].map { |p| p["id"] }
      expect(ids).not_to include(whisper.id)
    end

    it "includes the whisper in a target's topic JSON" do
      sign_in(target)
      get "/t/#{topic.id}.json"
      ids = response.parsed_body["post_stream"]["posts"].map { |p| p["id"] }
      expect(ids).to include(whisper.id)
    end

    it "includes the whisper in an admin's topic JSON" do
      sign_in(admin)
      get "/t/#{topic.id}.json"
      ids = response.parsed_body["post_stream"]["posts"].map { |p| p["id"] }
      expect(ids).to include(whisper.id)
    end
  end

  describe "GET /raw/:topic_id/:post_number (raw text endpoint)" do
    it "denies raw access to a stranger" do
      sign_in(stranger)
      get "/raw/#{topic.id}/#{whisper.post_number}"
      expect(response.status).to be_in([403, 404])
    end

    it "denies raw access to an anonymous viewer" do
      get "/raw/#{topic.id}/#{whisper.post_number}"
      expect(response.status).to be_in([403, 404])
    end

    it "allows raw access to the author" do
      sign_in(author)
      get "/raw/#{topic.id}/#{whisper.post_number}"
      expect(response.status).to eq(200)
    end

    it "allows raw access to the target" do
      sign_in(target)
      get "/raw/#{topic.id}/#{whisper.post_number}"
      expect(response.status).to eq(200)
    end
  end

  describe "GET /posts/:id/cooked.json (rendered HTML endpoint)" do
    it "denies cooked access to a stranger" do
      sign_in(stranger)
      get "/posts/#{whisper.id}/cooked.json"
      expect(response.status).to be_in([403, 404])
    end

    it "allows cooked access to the target" do
      sign_in(target)
      get "/posts/#{whisper.id}/cooked.json"
      expect(response.status).to eq(200)
    end
  end
end
