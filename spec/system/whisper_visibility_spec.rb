# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for who can SEE a whisper, across every read path:
# the topic stream, the search results page, the reply composer auto-arm,
# the category-group-moderator oversight role, and the plugin's master
# switch. A screenshot is captured at every meaningful UI step.
RSpec.describe "Whisper visibility", type: :system do
  fab!(:author) { Fabricate(:user, username: "author_amy") }
  fab!(:recipient) { Fabricate(:user, username: "target_tom") }
  fab!(:recipient_two) { Fabricate(:user, username: "target_tina") }
  fab!(:stranger) { Fabricate(:user, username: "stranger_sam") }
  fab!(:admin)
  fab!(:moderator)
  fab!(:cat_mod) { Fabricate(:user, username: "catmod_carl") }
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, title: "A thread with a whisper in it") }
  fab!(:op) { Fabricate(:post, topic: topic, user: author, raw: "The public original post.") }

  let(:whisper_body) { "This whispered message is for the chosen few only." }

  before do
    SiteSetting.discourse_whisper_enabled = true
    SiteSetting.min_post_length = 5
    SiteSetting.body_min_entropy = 1
    SearchIndexer.enable
  end

  def shot(name)
    begin
      Timeout.timeout(8) do
        until page.evaluate_script(
                "Array.from(document.images).every((i) => i.complete)",
              )
          sleep 0.1
        end
      end
    rescue Timeout::Error
      # Capture anyway rather than failing the spec over a slow image.
    end
    page.save_screenshot("#{name}.png")
  end

  # Creates a whisper post directly: a normal post plus the
  # whisper_target_user_ids custom field the composer would have set.
  def whisper!(target_ids, raw: whisper_body, by: author)
    post = Fabricate(:post, topic: topic, user: by, raw: raw)
    post.custom_fields["whisper_target_user_ids"] = target_ids
    post.save_custom_fields(true)
    SearchIndexer.index(post, force: true)
    post
  end

  def visit_topic
    visit("/t/#{topic.slug}/#{topic.id}")
    expect(page).to have_css("#topic-title", wait: 10)
  end

  context "a single-target whisper in the topic stream" do
    it "shows the whisper banner to the target recipient" do
      whisper!([recipient.id])
      sign_in(recipient)
      visit_topic

      expect(page).to have_css(
        "article.topic-post.whisper-to-user .whisper-target-banner",
        wait: 10,
      )
      expect(page).to have_css(".cooked", text: whisper_body)
      shot("09_recipient_sees_whisper")
    end

    it "hides the whisper entirely from a non-recipient" do
      whisper!([recipient.id])
      sign_in(stranger)
      visit_topic

      expect(page).to have_css(".cooked", text: "The public original post.")
      expect(page).to have_no_css(".whisper-target-banner")
      expect(page).to have_no_css(".cooked", text: whisper_body)
      shot("10_stranger_does_not_see_whisper")
    end

    it "shows the whisper to a site admin for oversight" do
      whisper!([recipient.id])
      sign_in(admin)
      visit_topic

      expect(page).to have_css(
        "article.topic-post.whisper-to-user .whisper-target-banner",
        wait: 10,
      )
      shot("11_admin_oversight_view")
    end

    it "shows the whisper to a site moderator for oversight" do
      whisper!([recipient.id])
      sign_in(moderator)
      visit_topic

      expect(page).to have_css(
        "article.topic-post.whisper-to-user .whisper-target-banner",
        wait: 10,
      )
      shot("12_moderator_oversight_view")
    end
  end

  context "a multi-target whisper" do
    it "lists every recipient in the banner" do
      whisper!([recipient.id, recipient_two.id])
      sign_in(recipient_two)
      visit_topic

      expect(page).to have_css(".whisper-target-banner", wait: 10)
      expect(page).to have_css(
        ".whisper-target-banner .whisper-target-user",
        text: "@#{recipient.username}",
      )
      expect(page).to have_css(
        ".whisper-target-banner .whisper-target-user",
        text: "@#{recipient_two.username}",
      )
      shot("13_multi_user_whisper_banner")
    end
  end

  context "replying to a whisper" do
    it "auto-arms a whisper back to the rest of the audience" do
      wp = whisper!([recipient.id, recipient_two.id])
      sign_in(recipient)
      visit_topic

      expect(page).to have_css(".whisper-target-banner", wait: 10)
      within("article[data-post-number='#{wp.post_number}']") do
        find(
          ".post-controls .post-action-menu__reply, .post-controls .reply",
          match: :first,
        ).click
      end

      expect(page).to have_css(".d-editor-input", wait: 10)
      expect(page).to have_css(".whisper-composer-target-pill", wait: 10)
      shot("14_reply_composer_auto_armed")
    end
  end

  context "the search results page" do
    it "returns the whisper to a recipient searching for its text" do
      whisper!([recipient.id], raw: "Searchable whisper pumpkinseed marker.")
      sign_in(recipient)

      visit("/search?q=pumpkinseed")
      expect(page).to have_css(".search-query", wait: 10)
      expect(page).to have_css(
        ".fps-result",
        text: "pumpkinseed",
        wait: 10,
      )
      shot("15_search_recipient_sees_hit")
    end

    it "does not return the whisper to a stranger searching for its text" do
      whisper!([recipient.id], raw: "Searchable whisper pumpkinseed marker.")
      sign_in(stranger)

      visit("/search?q=pumpkinseed")
      expect(page).to have_css(".search-query", wait: 10)
      expect(page).to have_no_css(".fps-result", text: "pumpkinseed", wait: 5)
      shot("16_search_stranger_no_hit")
    end
  end

  context "category group moderator oversight" do
    before do
      SiteSetting.enable_category_group_moderation = true
      group = Fabricate(:group)
      group.add(cat_mod)
      category.update!(reviewable_by_group: group)
    end

    it "shows a mixed-audience whisper to a category group moderator" do
      whisper!([recipient.id])
      sign_in(cat_mod)
      visit_topic

      expect(page).to have_css(
        "article.topic-post.whisper-to-user .whisper-target-banner",
        wait: 10,
      )
      shot("17_category_moderator_oversight")
    end
  end

  context "when the plugin is disabled" do
    it "shows the whisper post to everyone, with no banner" do
      whisper!([recipient.id])
      SiteSetting.discourse_whisper_enabled = false
      sign_in(stranger)
      visit_topic

      expect(page).to have_css(".cooked", text: whisper_body, wait: 10)
      expect(page).to have_no_css(".whisper-target-banner")
      shot("18_plugin_disabled_visible_to_all")
    end
  end

  context "the admin site setting" do
    it "exposes the master switch under the Discourse Whisper category" do
      sign_in(admin)
      visit("/admin/site_settings/category/discourse_whisper")
      expect(page).to have_css(
        ".admin-detail .setting[data-setting='discourse_whisper_enabled'], .setting[data-setting='discourse_whisper_enabled']",
        wait: 10,
      )
      shot("19_admin_site_setting")
    end
  end
end
