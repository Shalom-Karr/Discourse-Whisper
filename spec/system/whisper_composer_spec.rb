# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for arming a whisper from the composer: the toolbar
# eye button + modal, the @mention hint shortcut, the armed pill, and
# posting a whisper. A screenshot is captured at every meaningful UI step;
# screenshots are written to tmp/capybara/ and published as the CI artifact.
RSpec.describe "Whisper composer", type: :system do
  # TL2 + refreshed auto-groups so the author's posts are not held for
  # approval — that would keep a posted whisper out of the topic stream.
  fab!(:author) do
    Fabricate(:user, username: "author_amy", trust_level: TrustLevel[2], refresh_auto_groups: true)
  end
  fab!(:recipient_one) { Fabricate(:user, username: "target_tom") }
  fab!(:recipient_two) { Fabricate(:user, username: "target_tina") }
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, title: "A thread to whisper in") }
  fab!(:post) { Fabricate(:post, topic: topic, raw: "The original post in this thread.") }

  before do
    SiteSetting.discourse_whisper_enabled = true
    SiteSetting.min_post_length = 5
    SiteSetting.body_min_entropy = 1
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

  def open_reply_composer
    find("#topic-footer-buttons .create", match: :first).click
    expect(page).to have_css(".d-editor-input", wait: 10)
  end

  def whisper_toolbar_button
    find(
      ".d-editor-button-bar button[title='#{I18n.t("js.discourse_whisper.toolbar.title")}']",
    )
  end

  context "a user arms a whisper from the toolbar eye button" do
    before { sign_in(author) }

    it "opens the modal, picks users, and arms the whisper pill" do
      visit("/t/#{topic.slug}/#{topic.id}")
      expect(page).to have_css("#topic-title", wait: 10)

      open_reply_composer
      expect(page).to have_css(
        ".d-editor-button-bar button[title='#{I18n.t("js.discourse_whisper.toolbar.title")}']",
        wait: 10,
      )
      shot("01_composer_toolbar_eye_button")

      whisper_toolbar_button.click
      expect(page).to have_css(".whisper-target-modal", wait: 10)
      expect(page).to have_css(".whisper-target-modal__instructions")
      shot("02_whisper_modal_empty")

      chooser =
        PageObjects::Components::SelectKit.new(
          ".whisper-target-modal .email-group-user-chooser",
        )
      chooser.expand
      chooser.search(recipient_one.username)
      chooser.select_row_by_value(recipient_one.username)
      chooser.search(recipient_two.username)
      chooser.select_row_by_value(recipient_two.username)
      shot("03_whisper_modal_users_selected")

      # Collapse the user picker so its dropdown stops overlapping the
      # modal footer, otherwise the confirm button click is intercepted.
      chooser.collapse
      find(".whisper-target-modal .btn-primary").click
      expect(page).to have_no_css(".whisper-target-modal", wait: 10)

      expect(page).to have_css(".whisper-composer-target-pill", wait: 10)
      expect(page).to have_css(
        ".whisper-composer-target-pill__user",
        text: "@#{recipient_one.username}",
      )
      shot("04_composer_armed_pill")

      find(".d-editor-input").fill_in(with: "A private aside for the two of you.")
      find(".save-or-cancel .create").click

      expect(page).to have_css(
        ".cooked.whisper-to-user .whisper-target-banner",
        wait: 15,
      )
      shot("05_whisper_posted_author_view")

      whisper_post = topic.reload.posts.last
      expect(whisper_post.custom_fields["whisper_target_user_ids"]).to(
        match_array([recipient_one.id, recipient_two.id]),
      )
    end
  end

  context "a user arms a whisper from the @mention hint" do
    before { sign_in(author) }

    it "shows the hint when a mention is typed and arms on click" do
      visit("/t/#{topic.slug}/#{topic.id}")
      expect(page).to have_css("#topic-title", wait: 10)

      open_reply_composer
      find(".d-editor-input").fill_in(
        with: "Hey @#{recipient_one.username}, a quick note for you.",
      )

      expect(page).to have_css(".whisper-mention-hint", wait: 10)
      expect(page).to have_css(
        ".whisper-mention-hint__btn",
        text: recipient_one.username,
      )
      shot("06_mention_hint_pill")

      find(".whisper-mention-hint__btn").click
      expect(page).to have_css(".whisper-composer-target-pill", wait: 10)
      expect(page).to have_css(
        ".whisper-composer-target-pill__user",
        text: "@#{recipient_one.username}",
      )
      shot("07_whisper_armed_via_mention_hint")
    end
  end

  context "a user clears an armed whisper" do
    before { sign_in(author) }

    it "removes the pill when the clear button is clicked" do
      visit("/t/#{topic.slug}/#{topic.id}")
      expect(page).to have_css("#topic-title", wait: 10)

      open_reply_composer
      whisper_toolbar_button.click
      expect(page).to have_css(".whisper-target-modal", wait: 10)

      chooser =
        PageObjects::Components::SelectKit.new(
          ".whisper-target-modal .email-group-user-chooser",
        )
      chooser.expand
      chooser.search(recipient_one.username)
      chooser.select_row_by_value(recipient_one.username)
      chooser.collapse
      find(".whisper-target-modal .btn-primary").click

      expect(page).to have_css(".whisper-composer-target-pill", wait: 10)
      shot("08_armed_pill_before_clearing")

      find(".whisper-composer-target-pill__close").click
      expect(page).to have_no_css(".whisper-composer-target-pill", wait: 10)
    end
  end
end
