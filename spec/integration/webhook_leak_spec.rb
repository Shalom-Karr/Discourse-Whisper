# frozen_string_literal: true

require "rails_helper"

# Whisper posts must never be dispatched to webhook URLs. The plugin prepends
# `DiscourseWhisper::WebHookExtension` onto `WebHook.singleton_class` to drop
# the enqueue for any post with a `whisper_target_user_ids` custom field.
RSpec.describe "discourse-whisper webhook leak coverage" do
  fab!(:author, :user)
  fab!(:target, :user)
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:web_hook)

  before do
    SiteSetting.discourse_whisper_enabled = true
    Jobs.run_immediately!
  end

  def whisper_post
    post =
      Fabricate(
        :post,
        topic: topic,
        user: author,
        raw: "Secret whisper body — must not reach the webhook endpoint.",
      )
    post.custom_fields["whisper_target_user_ids"] = [target.id]
    post.save_custom_fields
    post
  end

  def normal_post
    Fabricate(:post, topic: topic, user: author, raw: "Public post body, no whisper.")
  end

  it "does NOT enqueue a post webhook for a whisper post" do
    enqueued_ids = []
    allow(Jobs).to receive(:enqueue) do |job, args|
      enqueued_ids << args[:id] if job == :emit_web_hook_event
    end

    post = whisper_post
    WebHook.enqueue_post_hooks(:post_created, post)

    expect(enqueued_ids).not_to include(post.id)
  end

  it "DOES enqueue a post webhook for a normal (non-whisper) post (baseline)" do
    enqueued_ids = []
    allow(Jobs).to receive(:enqueue) do |job, args|
      enqueued_ids << args[:id] if job == :emit_web_hook_event
    end

    post = normal_post
    WebHook.enqueue_post_hooks(:post_created, post)

    expect(enqueued_ids).to include(post.id),
    "Discourse's webhook plumbing appears broken in this env — the whisper " \
      "block relies on it firing for normal posts."
  end

  it "blocks post_edited webhooks for whisper posts" do
    enqueued_ids = []
    allow(Jobs).to receive(:enqueue) do |job, args|
      enqueued_ids << args[:id] if job == :emit_web_hook_event
    end

    post = whisper_post
    WebHook.enqueue_post_hooks(:post_edited, post)

    expect(enqueued_ids).not_to include(post.id)
  end

  it "blocks post_destroyed webhooks for whisper posts" do
    enqueued_ids = []
    allow(Jobs).to receive(:enqueue) do |job, args|
      enqueued_ids << args[:id] if job == :emit_web_hook_event
    end

    post = whisper_post
    WebHook.enqueue_post_hooks(:post_destroyed, post)

    expect(enqueued_ids).not_to include(post.id)
  end

  it "blocks post_recovered webhooks for whisper posts" do
    enqueued_ids = []
    allow(Jobs).to receive(:enqueue) do |job, args|
      enqueued_ids << args[:id] if job == :emit_web_hook_event
    end

    post = whisper_post
    WebHook.enqueue_post_hooks(:post_recovered, post)

    expect(enqueued_ids).not_to include(post.id)
  end

  it "does not block when the plugin is disabled" do
    SiteSetting.discourse_whisper_enabled = false
    enqueued_ids = []
    allow(Jobs).to receive(:enqueue) do |job, args|
      enqueued_ids << args[:id] if job == :emit_web_hook_event
    end

    post = whisper_post
    WebHook.enqueue_post_hooks(:post_created, post)

    expect(enqueued_ids).to include(post.id)
  end

  it "does not interfere with topic-level webhooks for non-whisper content" do
    Fabricate(:topic_web_hook)
    enqueued_ids = []
    allow(Jobs).to receive(:enqueue) do |job, args|
      enqueued_ids << args[:id] if job == :emit_web_hook_event
    end

    WebHook.enqueue_topic_hooks(:topic_created, topic)
    expect(enqueued_ids).to include(topic.id)
  end

  it "the full post_created PostCreator flow does not enqueue a webhook for a whisper" do
    # End-to-end check: create the whisper through PostCreator (the real path)
    # and confirm no webhook event is queued for it.
    enqueued_events = []
    allow(Jobs).to receive(:enqueue) do |job, args|
      enqueued_events << args if job == :emit_web_hook_event
    end

    post =
      PostCreator.new(
        author,
        topic_id: topic.id,
        raw: "End-to-end whisper via PostCreator — webhook must NOT fire.",
        whisper_target_user_ids: [target.id],
      ).create!

    post_events = enqueued_events.select { |a| a[:event_type] == "post" && a[:id] == post.id }
    expect(post_events).to be_empty
  end
end
