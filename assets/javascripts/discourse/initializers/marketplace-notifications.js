import { apiInitializer } from "discourse/lib/api";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const MESSAGE_PREFIX = "marketplace.notifications.";

export default apiInitializer((api) => {
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
          if (this.notification.data.transaction_id) {
            return getURL(
              `/marketplace/listings/${this.notification.data.listing_id}?transaction_id=${this.notification.data.transaction_id}`
            );
          }

          if (this.notification.data.offer_id) {
            return getURL(
              `/marketplace/listings/${this.notification.data.listing_id}`
            );
          }
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
