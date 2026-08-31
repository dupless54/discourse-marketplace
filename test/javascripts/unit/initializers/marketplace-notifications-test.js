import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import {
  getRenderDirector,
  resetNotificationTypeRenderers,
} from "discourse/lib/notification-types-manager";
import marketplaceNotifications from "discourse/plugins/discourse-marketplace/discourse/initializers/marketplace-notifications";

const CUSTOM_TYPE = "custom";
const SITE = { notificationLookup: { 14: CUSTOM_TYPE } };

module("Unit | Initializer | marketplace-notifications", function (hooks) {
  setupTest(hooks);

  hooks.beforeEach(function () {
    marketplaceNotifications.initialize(this.owner);
  });

  hooks.afterEach(function () {
    // This registers a renderer for the shared "custom" notification type,
    // not one scoped to Marketplace -- must not leak into other tests.
    resetNotificationTypeRenderers();
  });

  test("links a Marketplace notification to its listing, with a stable icon and a plain description", function (assert) {
    const notification = {
      notification_type: 14,
      data: {
        message: "marketplace.notifications.transaction_started",
        display_username: "buyer1",
        topic_title: "Vintage Synthesizer",
        listing_id: 42,
        transaction_id: 314,
        title: "marketplace.notifications.transaction_started_title",
      },
    };

    const director = getRenderDirector(
      CUSTOM_TYPE,
      notification,
      null,
      {},
      SITE
    );

    assert.strictEqual(director.icon, "tag");
    assert.true(
      director.linkHref.endsWith("/marketplace/listings/42?transaction_id=314"),
      `linkHref (${director.linkHref}) points at the exact transaction`
    );
    assert.true(director.description.includes("Vintage Synthesizer"));
    assert.true(director.description.includes("buyer1"));
    assert.strictEqual(
      director.label,
      undefined,
      "no separate label -- the full sentence lives in description"
    );
  });

  test("does not change how a non-Marketplace custom notification renders", function (assert) {
    const notification = {
      notification_type: 14,
      data: { message: "some_other_plugin.thing" },
    };

    const director = getRenderDirector(
      CUSTOM_TYPE,
      notification,
      null,
      {},
      SITE
    );

    assert.strictEqual(
      director.icon,
      "notification.some_other_plugin.thing",
      "falls back to core's default custom-notification icon behavior"
    );
    assert.strictEqual(director.linkHref, undefined);
  });
});
