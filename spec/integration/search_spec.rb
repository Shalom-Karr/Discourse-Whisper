# frozen_string_literal: true

require "rails_helper"

RSpec.describe "discourse-whisper search visibility" do
  fab!(:author, :user)
  fab!(:target, :user)
  fab!(:stranger, :user)
  fab!(:admin)
  fab!(:topic) { Fabricate(:topic, user: author) }

  let(:needle) { "uniqueneedlewhispercontent12345abcxyz" }

  fab!(:whisper) do |_example|
    post =
      Fabricate(
        :post,
        topic: topic,
        user: author,
        raw: "This post contains uniqueneedlewhispercontent12345abcxyz for search testing.",
      )
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end

  before do
    SiteSetting.discourse_whisper_enabled = true
    SearchIndexer.enable
    SearchIndexer.index(whisper, force: true)
  end

  def search_post_ids(user)
    Search.execute(needle, guardian: Guardian.new(user)).posts.map(&:id)
  end

  it "does not surface the whisper for a stranger" do
    expect(search_post_ids(stranger)).not_to include(whisper.id)
  end

  it "does not surface the whisper for an anonymous viewer" do
    expect(search_post_ids(nil)).not_to include(whisper.id)
  end

  it "surfaces the whisper for the target user" do
    expect(search_post_ids(target)).to include(whisper.id)
  end

  it "surfaces the whisper for the author" do
    expect(search_post_ids(author)).to include(whisper.id)
  end

  it "surfaces the whisper for an admin" do
    expect(search_post_ids(admin)).to include(whisper.id)
  end

  context "when the plugin is disabled" do
    before { SiteSetting.discourse_whisper_enabled = false }

    it "surfaces the whisper for a stranger (no visibility enforcement)" do
      expect(search_post_ids(stranger)).to include(whisper.id)
    end
  end

  context "with topic-context search (searching within the whisper's topic)" do
    it "does not surface the whisper to a stranger searching inside the topic" do
      results = Search.execute(needle, guardian: Guardian.new(stranger), search_context: topic)
      expect(results.posts.map(&:id)).not_to include(whisper.id)
    end

    it "surfaces the whisper to the target searching inside the topic" do
      results = Search.execute(needle, guardian: Guardian.new(target), search_context: topic)
      expect(results.posts.map(&:id)).to include(whisper.id)
    end
  end
end
