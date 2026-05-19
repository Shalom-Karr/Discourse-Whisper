import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import WhisperTargetModal from "../components/whisper-target-modal";
import { computeReplyAudience } from "../lib/reply-audience";

export default {
  name: "discourse-whisper",

  initialize() {
    withPluginApi((api) => {
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

      api.serializeOnCreate("whisper_target_user_ids", "whisperTargetUserIds");

      // `addTrackedPostProperties` is the modern replacement for the
      // deprecated `includePostAttributes` — it surfaces the serializer
      // attributes on the post model, which the cooked-element decorator
      // below relies on to know a post is a whisper.
      if (api.addTrackedPostProperties) {
        api.addTrackedPostProperties(
          "is_whisper_to_user",
          "whisper_target_user_ids",
          "whisper_targets"
        );
      } else {
        api.includePostAttributes(
          "is_whisper_to_user",
          "whisper_target_user_ids",
          "whisper_targets"
        );
      }

      api.decorateCookedElement(
        (cookedEl, helper) => {
          const post = helper?.getModel?.();
          // eslint-disable-next-line no-console
          console.log("[whisper-debug] decorate", {
            hasHelper: !!helper,
            hasPost: !!post,
            isWhisper: post?.is_whisper_to_user,
            targetsLen: Array.isArray(post?.whisper_targets)
              ? post.whisper_targets.length
              : "n/a",
          });
          if (!post?.is_whisper_to_user) {
            return;
          }

          const article = cookedEl.closest("article.topic-post");
          if (article) {
            article.classList.add("whisper-to-user");
          }

          const parent = cookedEl.parentElement;
          if (
            !parent ||
            parent.querySelector(":scope > .whisper-target-banner")
          ) {
            return;
          }

          const targets = Array.isArray(post.whisper_targets)
            ? post.whisper_targets
            : [];
          if (!targets.length) {
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
          label.textContent = ` ${i18n("discourse_whisper.post.whisper_to")} `;
          banner.appendChild(label);

          targets.forEach((t, i) => {
            if (i > 0) {
              const sep = document.createElement("span");
              sep.className = "whisper-target-sep";
              sep.textContent = ", ";
              banner.appendChild(sep);
            }
            const link = document.createElement("a");
            link.className = "whisper-target-user";
            link.href = `/u/${t.username}`;
            link.textContent = `@${t.username}`;
            banner.appendChild(link);
          });

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

        const replyAudience = computeReplyAudience(post, currentUser.id);
        if (!replyAudience.length) {
          return;
        }

        model.set(
          "whisperTargetUserIds",
          replyAudience.map((u) => u.id)
        );
        model.set(
          "whisperTargetUsernames",
          replyAudience.map((u) => u.username)
        );
        model.set("whisperTargets", replyAudience);
      });
    });
  },
};
