import Service from "@ember/service";
import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import MarketplaceListingCard from "discourse/plugins/discourse-marketplace/discourse/components/marketplace-listing-card";

// A stubbed real composer service, not a sinon method stub -- openNewMessage
// is an @action-decorated accessor, and directly overwriting it (whether by
// assignment or via sinon.stub) does not reliably reach the call the
// component's `{{on "click"}}` handler makes. Swapping the whole service
// registration is the same pattern discourse/tests/helpers/component-test.js
// itself uses for current-user/topic-tracking-state.
class FakeComposerService extends Service {
  lastOpenNewMessageArgs = null;

  openNewMessage(args) {
    this.lastOpenNewMessageArgs = args;
  }
}

module("Integration | Component | MarketplaceListingCard", function (hooks) {
  setupRenderingTest(hooks);

  test("shows Buy and Message Seller for an eligible, logged-in non-seller", async function (assert) {
    this.listing = {
      id: 1,
      title: "Vintage Synthesizer",
      status: "active",
      price_cents: 15000,
      currency: "USD",
      thumbnail_url: "/uploads/default/original/1X/synth.png",
      inventory_mode: "single",
      purchasable: true,
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };

    await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);

    assert.dom(".marketplace-listing-card__image").exists("the thumbnail image is shown");
    assert
      .dom(".marketplace-listing-card__title")
      .hasText("Vintage Synthesizer");
    assert.dom(".marketplace-listing-card__message").exists("Message Seller is offered");
    assert.dom(".marketplace-listing-card__buy").exists("Buy is offered");
    assert.dom(".marketplace-listing-card__edit").doesNotExist();
  });

  test("shows a placeholder instead of an image when there is no thumbnail", async function (assert) {
    this.listing = {
      id: 2,
      title: "No photo listing",
      status: "active",
      price_cents: 500,
      currency: "USD",
      thumbnail_url: null,
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };

    await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);

    assert.dom(".marketplace-listing-card__image").doesNotExist();
    assert.dom(".marketplace-listing-card__placeholder").exists();
  });

  test("shows owner actions instead of Buy/Message Seller when the viewer is the seller", async function (assert) {
    this.listing = {
      id: 3,
      title: "My own listing",
      status: "draft",
      price_cents: 500,
      currency: "USD",
      seller: { id: this.currentUser.id, username: this.currentUser.username },
    };

    await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);

    assert.dom(".marketplace-listing-card__edit").exists("an owner edit action is shown");
    assert.dom(".marketplace-listing-card__buy").doesNotExist();
    assert.dom(".marketplace-listing-card__message").doesNotExist();
  });

  test("opens a prefilled PM to the seller when Message Seller is clicked", async function (assert) {
    this.owner.unregister("service:composer");
    this.owner.register("service:composer", FakeComposerService);

    this.listing = {
      id: 5,
      title: "Vintage Synthesizer",
      status: "active",
      price_cents: 15000,
      currency: "USD",
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };

    await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);
    await click(".marketplace-listing-card__message");

    const openedWith =
      this.owner.lookup("service:composer").lastOpenNewMessageArgs;
    assert.ok(openedWith, "openNewMessage was called");
    assert.strictEqual(openedWith.recipients, "seller_user");
    assert.true(openedWith.title.includes("Vintage Synthesizer"));
  });

  test("shows remaining stock and offers Buy for an in-stock finite listing", async function (assert) {
    this.listing = {
      id: 10,
      title: "Limited run poster",
      status: "active",
      price_cents: 2000,
      currency: "USD",
      inventory_mode: "finite",
      stock_available: 3,
      purchasable: true,
      expired: false,
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };

    await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);

    assert
      .dom(".marketplace-listing-card__availability")
      .hasText("3 left");
    assert.dom(".marketplace-listing-card__buy").exists();
  });

  test("shows out of stock and hides Buy for a sold-out finite listing", async function (assert) {
    this.listing = {
      id: 11,
      title: "Sold out poster",
      status: "active",
      price_cents: 2000,
      currency: "USD",
      inventory_mode: "finite",
      stock_available: 0,
      purchasable: false,
      expired: false,
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };

    await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);

    assert.dom(".marketplace-listing-card__availability").hasText("Out of stock");
    assert.dom(".marketplace-listing-card__buy").doesNotExist();
  });

  test("shows an unlimited stock indicator and offers Buy", async function (assert) {
    this.listing = {
      id: 12,
      title: "Digital download",
      status: "active",
      price_cents: 500,
      currency: "USD",
      inventory_mode: "unlimited",
      purchasable: true,
      expired: false,
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };

    await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);

    assert.dom(".marketplace-listing-card__availability").hasText("Unlimited stock");
    assert.dom(".marketplace-listing-card__buy").exists();
  });

  test("shows expired and hides Buy for an expired active listing", async function (assert) {
    this.listing = {
      id: 13,
      title: "Expired listing",
      status: "active",
      price_cents: 500,
      currency: "USD",
      inventory_mode: "single",
      purchasable: false,
      expired: true,
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };

    await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);

    assert.dom(".marketplace-listing-card__availability").hasText("Expired");
    assert.dom(".marketplace-listing-card__buy").doesNotExist();
  });
});

module(
  "Integration | Component | MarketplaceListingCard | anonymous",
  function (hooks) {
    setupRenderingTest(hooks, { anonymous: true });

    test("hides Buy, Message Seller, and owner actions for anonymous visitors", async function (assert) {
      this.listing = {
        id: 6,
        title: "Anonymous view",
        status: "active",
        price_cents: 500,
        currency: "USD",
        seller: { id: 999, username: "seller_user" },
      };

      await render(<template><MarketplaceListingCard @listing={{this.listing}} /></template>);

      assert.dom(".marketplace-listing-card__buy").doesNotExist();
      assert.dom(".marketplace-listing-card__message").doesNotExist();
      assert.dom(".marketplace-listing-card__edit").doesNotExist();
    });
  }
);
