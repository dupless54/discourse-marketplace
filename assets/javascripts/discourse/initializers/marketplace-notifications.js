import getURL from "discourse/lib/get-url";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

// Marketplace has no topic/post of its own to notify against (see
// lib/marketplace/notifier.rb), so it uses Notification.types[:custom] --
// the only notification type a plugin outside Discourse core can safely
// use without a core PR to extend the Notification.types enum (verified:
// third-party plugins have no register_notification_type API; every enum
// value beyond :custom, like discourse-reactions' :reaction, is added by
// core itself for a bundled plugin).
//
// api.registerNotificationTypeRenderer("your_type", ...) is keyed by that
// same enum value (see its doc comment in plugin-api.gjs), so registering
// for "custom" here replaces the renderer for every :custom notification on
// the site, not just Marketplace's -- registering our own dedicated type
// isn't an option (see above). The two getters core's own default renderer
// (discourse/lib/notification-types/custom.js) overrides -- icon and
// linkTitle -- are reproduced byte-for-byte below for the non-Marketplace
// branch, and every other getter defers to `super`, i.e. the same
// NotificationTypeBase behavior a plain :custom notification already gets
// today. Only Marketplace's own notifications (identified by their
// "marketplace.notifications." message prefix) get different treatment:
// a stable icon, a link back to the listing, and a plain-text description
// instead of a topic-derived one.
const MESSAGE_PREFIX = "marketplace.notifications.";

export default {
  name: "marketplace-notifications",

  initialize() {
    withPluginApi((api) => {
      api.registerNotificationTypeRenderer("custom", (NotificationTypeBase) => {
        return class extends NotificationTypeBase {
          get isMarketplace() {
            return (
              typeof this.notification.data.message === "string" &&
              this.notification.data.message.startsWith(MESSAGE_PREFIX)
            );
          }

          get icon() {
            if (this.isMarketplace) {
              return "tag";
            }
            return `notification.${this.notification.data.message}`;
          }

          get linkTitle() {
            if (this.notification.data.title) {
              return i18n(this.notification.data.title);
            }
          }

          get linkHref() {
            if (this.isMarketplace && this.notification.data.listing_id) {
              return getURL(
                `/marketplace/listings/${this.notification.data.listing_id}`
              );
            }
            return super.linkHref;
          }

          get label() {
            if (this.isMarketplace) {
              return undefined;
            }
            return super.label;
          }

          get description() {
            if (this.isMarketplace) {
              return i18n(this.notification.data.message, {
                username: this.notification.data.display_username,
                listing_title: this.notification.data.topic_title,
              });
            }
            return super.description;
          }
        };
      });
    });
  },
};
