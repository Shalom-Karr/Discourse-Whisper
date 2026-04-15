import { withPluginApi } from "discourse/lib/plugin-api";
import WhisperTargetModal from "../components/whisper-target-modal";

export default {
  name: "discourse-whisper",

  initialize() {
    withPluginApi("1.8.0", (api) => {
      const siteSettings = api.container.lookup("service:site-settings");
      if (!siteSettings?.discourse_whisper_enabled) {
        return;
      }

      api.modifyClass("model:composer", {
        pluginId: "discourse-whisper",
      });

      api.onToolbarCreate((toolbar) => {
        toolbar.addButton({
          id: "discourse-whisper-target",
          group: "extras",
          icon: "far-eye",
          title: "discourse_whisper.toolbar.title",
          perform: () => {
            const modal = api.container.lookup("service:modal");
            const composerService = api.container.lookup("service:composer");
            modal?.show(WhisperTargetModal, {
              model: { composer: composerService?.model },
            });
          },
        });
      });

      api.serializeOnCreate("whisper_target_user_id", "whisperTargetUserId");

      api.includePostAttributes(
        "is_whisper_to_user",
        "whisper_target_user_id",
        "whisper_target_username",
        "whisper_target_avatar_template"
      );

      api.decorateCookedElement(
        (cookedEl, helper) => {
          if (!helper) {
            return;
          }
          const post = helper.getModel?.();
          if (!post?.is_whisper_to_user) {
            return;
          }

          const article = cookedEl.closest("article.topic-post");
          if (article) {
            article.classList.add("whisper-to-user");
          }

          const parent = cookedEl.parentElement;
          if (!parent || parent.querySelector(":scope > .whisper-target-banner")) {
            return;
          }

          const banner = document.createElement("div");
          banner.className = "whisper-target-banner";

          const svgNS = "http://www.w3.org/2000/svg";
          const icon = document.createElementNS(svgNS, "svg");
          icon.setAttribute("viewBox", "0 0 24 24");
          icon.setAttribute("width", "14");
          icon.setAttribute("height", "14");
          icon.setAttribute("aria-hidden", "true");
          icon.classList.add("whisper-eye");
          const path = document.createElementNS(svgNS, "path");
          path.setAttribute("fill", "currentColor");
          path.setAttribute(
            "d",
            "M12 5c-7 0-10 7-10 7s3 7 10 7 10-7 10-7-3-7-10-7zm0 11a4 4 0 110-8 4 4 0 010 8z"
          );
          icon.appendChild(path);
          banner.appendChild(icon);

          const label = document.createElement("span");
          label.className = "whisper-target-label";
          label.textContent = " whisper to ";
          banner.appendChild(label);

          const link = document.createElement("a");
          link.className = "whisper-target-user";
          link.href = `/u/${post.whisper_target_username}`;
          link.textContent = `@${post.whisper_target_username}`;
          banner.appendChild(link);

          parent.insertBefore(banner, cookedEl);
        },
        { id: "discourse-whisper-decorator", onlyStream: true }
      );

      api.onAppEvent("composer:opened", () => {
        const composerService = api.container.lookup("service:composer");
        const model = composerService?.model;
        if (!model) {
          return;
        }
        const post = model.post;
        if (!post?.is_whisper_to_user) {
          return;
        }
        const currentUser = api.getCurrentUser();
        if (!currentUser) {
          return;
        }

        let targetId = null;
        let targetUsername = null;
        let targetAvatar = null;

        if (post.user_id === currentUser.id) {
          targetId = post.whisper_target_user_id;
          targetUsername = post.whisper_target_username;
          targetAvatar = post.whisper_target_avatar_template;
        } else if (post.whisper_target_user_id === currentUser.id) {
          targetId = post.user_id;
          targetUsername = post.username;
          targetAvatar = post.avatar_template;
        }

        if (targetId) {
          model.set("whisperTargetUserId", targetId);
          model.set("whisperTargetUsername", targetUsername);
          model.set("whisperTargetAvatarTemplate", targetAvatar);
        }
      });
    });
  },
};
