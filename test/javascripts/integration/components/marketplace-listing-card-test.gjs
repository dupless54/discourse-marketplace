import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import MarketplaceListingCard from "discourse/plugins/discourse-marketplace/discourse/components/marketplace-listing-card";

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
    let openedWith = null;
    this.owner.lookup("service:composer").openNewMessage = (args) => {
      openedWith = args;
    };

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

    assert.strictEqual(openedWith.recipients, "seller_user");
    assert.true(openedWith.title.includes("Vintage Synthesizer"));
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
