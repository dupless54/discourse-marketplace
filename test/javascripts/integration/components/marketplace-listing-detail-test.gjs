import Service from "@ember/service";
import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import MarketplaceListingDetail from "discourse/plugins/discourse-marketplace/discourse/components/marketplace-listing-detail";

// See marketplace-listing-card-test.gjs for why this replaces the service
// wholesale rather than stubbing the @action-decorated openNewMessage method.
class FakeComposerService extends Service {
  lastOpenNewMessageArgs = null;

  openNewMessage(args) {
    this.lastOpenNewMessageArgs = args;
  }
}

module("Integration | Component | MarketplaceListingDetail", function (hooks) {
  setupRenderingTest(hooks);

  test("offers Message Seller to a logged-in non-seller and opens a prefilled PM", async function (assert) {
    this.owner.unregister("service:composer");
    this.owner.register("service:composer", FakeComposerService);

    this.listing = {
      id: 1,
      title: "Vintage Synthesizer",
      status: "active",
      price_cents: 15000,
      currency: "USD",
      cooked: "<p>A great synth.</p>",
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };
    this.transaction = null;

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transaction={{this.transaction}}
        />
      </template>
    );

    assert
      .dom(".marketplace-listing-detail__message-seller")
      .exists("Message Seller is offered to a non-seller");

    await click(".marketplace-listing-detail__message-seller");

    const openedWith =
      this.owner.lookup("service:composer").lastOpenNewMessageArgs;
    assert.ok(openedWith, "openNewMessage was called");
    assert.strictEqual(openedWith.recipients, "seller_user");
    assert.true(openedWith.title.includes("Vintage Synthesizer"));
  });

  test("does not offer Message Seller to the listing's own seller", async function (assert) {
    this.listing = {
      id: 2,
      title: "My own listing",
      status: "draft",
      price_cents: 500,
      currency: "USD",
      cooked: "<p>Description</p>",
      seller: { id: this.currentUser.id, username: this.currentUser.username },
    };
    this.transaction = null;

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transaction={{this.transaction}}
        />
      </template>
    );

    assert
      .dom(".marketplace-listing-detail__message-seller")
      .doesNotExist("the seller never sees Message Seller on their own listing");
  });

  test("shows remaining stock and offers Buy for an in-stock finite listing", async function (assert) {
    this.listing = {
      id: 20,
      title: "Limited run poster",
      status: "active",
      price_cents: 2000,
      currency: "USD",
      cooked: "<p>Limited run.</p>",
      inventory_mode: "finite",
      stock_available: 2,
      purchasable: true,
      expired: false,
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };
    this.transaction = null;

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transaction={{this.transaction}}
        />
      </template>
    );

    assert.dom(".marketplace-listing-detail__availability").hasText("2 left");
    assert.dom("button.btn-primary").exists("Buy is offered");
  });

  test("hides Buy and shows out of stock for a sold-out finite listing", async function (assert) {
    this.listing = {
      id: 21,
      title: "Sold out poster",
      status: "active",
      price_cents: 2000,
      currency: "USD",
      cooked: "<p>Sold out.</p>",
      inventory_mode: "finite",
      stock_available: 0,
      purchasable: false,
      expired: false,
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };
    this.transaction = null;

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transaction={{this.transaction}}
        />
      </template>
    );

    assert
      .dom(".marketplace-listing-detail__availability")
      .hasText("Out of stock");
    assert.dom("button.btn-primary").doesNotExist("Buy is not offered");
  });
});

module(
  "Integration | Component | MarketplaceListingDetail | anonymous",
  function (hooks) {
    setupRenderingTest(hooks, { anonymous: true });

    test("does not offer Message Seller to an anonymous visitor", async function (assert) {
      this.listing = {
        id: 3,
        title: "Anonymous view",
        status: "active",
        price_cents: 500,
        currency: "USD",
        cooked: "<p>Description</p>",
        seller: { id: 999, username: "seller_user" },
      };
      this.transaction = null;

      await render(
        <template>
          <MarketplaceListingDetail
            @listing={{this.listing}}
            @transaction={{this.transaction}}
          />
        </template>
      );

      assert.dom(".marketplace-listing-detail__message-seller").doesNotExist();
    });
  }
);
