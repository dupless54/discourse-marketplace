import Service from "@ember/service";
import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
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
    this.transactions = [];

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
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

  test("shows the hero image before the description section, with a lightbox link, and a category badge", async function (assert) {
    this.listing = {
      id: 30,
      title: "Photographed item",
      status: "active",
      price_cents: 1000,
      currency: "USD",
      cooked: "<p>Full description text.</p>",
      thumbnail_url: "/uploads/default/original/1X/photo.png",
      category: { id: 7, name: "Electronics", slug: "electronics" },
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };
    this.transactions = [];

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
        />
      </template>
    );

    const content = document.querySelector(
      ".marketplace-listing-detail__content"
    );
    const hero = content.querySelector(
      ".marketplace-listing-detail__hero-link"
    );
    const description = content.querySelector(
      ".marketplace-listing-detail__description"
    );

    assert.ok(hero, "the hero image link is rendered");
    assert.ok(description, "the description section is rendered");
    assert.true(
      !!(
        hero.compareDocumentPosition(description) &
        Node.DOCUMENT_POSITION_FOLLOWING
      ),
      "the hero image comes before the description section, not after it"
    );

    assert
      .dom(".marketplace-listing-detail__hero-link")
      .hasAttribute("href", "/uploads/default/original/1X/photo.png");
    assert.dom(".marketplace-listing-detail__hero-link").hasClass("lightbox");
    assert
      .dom(".marketplace-listing-detail__description-heading")
      .hasText("Listing Description");
    assert
      .dom(".marketplace-listing-detail__category")
      .hasText("Electronics");
  });

  test("renders no hero image or category badge when the listing has neither", async function (assert) {
    this.listing = {
      id: 31,
      title: "Plain listing",
      status: "active",
      price_cents: 1000,
      currency: "USD",
      cooked: "<p>Just text, no photo.</p>",
      seller: { id: this.currentUser.id + 1, username: "seller_user" },
    };
    this.transactions = [];

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
        />
      </template>
    );

    assert.dom(".marketplace-listing-detail__hero-link").doesNotExist();
    assert.dom(".marketplace-listing-detail__category").doesNotExist();
    assert
      .dom(".marketplace-listing-detail__description")
      .exists("the description section still renders on its own");
  });

  test("the Edit link on the owner's own listing routes to the correct edit URL", async function (assert) {
    this.listing = {
      id: 32,
      title: "My own listing",
      status: "draft",
      price_cents: 500,
      currency: "USD",
      cooked: "<p>Description</p>",
      seller: { id: this.currentUser.id, username: this.currentUser.username },
    };
    this.transactions = [];

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
        />
      </template>
    );

    assert
      .dom(".marketplace-listing-detail__edit")
      .hasAttribute("href", "/marketplace/listings/32/edit");
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
    this.transactions = [];

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
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
    this.transactions = [];

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
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
    this.transactions = [];

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
        />
      </template>
    );

    assert
      .dom(".marketplace-listing-detail__availability")
      .hasText("Out of stock");
    assert.dom("button.btn-primary").doesNotExist("Buy is not offered");
  });

  test("seller manages multiple pending transactions independently and sees history", async function (assert) {
    this.listing = {
      id: 22,
      title: "Multi-order listing",
      status: "active",
      price_cents: 2000,
      currency: "USD",
      cooked: "<p>Multiple units.</p>",
      inventory_mode: "finite",
      stock_available: 2,
      purchasable: true,
      expired: false,
      seller: {
        id: this.currentUser.id,
        username: this.currentUser.username,
      },
    };
    this.transactions = [
      {
        id: 101,
        buyer_id: this.currentUser.id + 1,
        seller_id: this.currentUser.id,
        status: "pending",
        buyer_confirmed_at: "2026-08-28T01:00:00.000Z",
        seller_confirmed_at: null,
        buyer: { id: this.currentUser.id + 1, username: "buyer_a" },
      },
      {
        id: 102,
        buyer_id: this.currentUser.id + 2,
        seller_id: this.currentUser.id,
        status: "pending",
        buyer_confirmed_at: null,
        seller_confirmed_at: null,
        buyer: { id: this.currentUser.id + 2, username: "buyer_b" },
      },
      {
        id: 90,
        buyer_id: this.currentUser.id + 1,
        seller_id: this.currentUser.id,
        status: "completed",
        buyer_confirmed_at: "2026-08-27T01:00:00.000Z",
        seller_confirmed_at: "2026-08-27T01:01:00.000Z",
        completed_at: "2026-08-27T01:01:00.000Z",
        buyer: { id: this.currentUser.id + 1, username: "buyer_a" },
      },
    ];
    this.pagination = { page: 1, per_page: 20, has_more: false };

    let confirmedTransactionId = null;
    pretender.post("/marketplace/transactions/101/confirm", () => {
      confirmedTransactionId = 101;
      return response({
        transaction: {
          ...this.transactions[0],
          status: "completed",
          seller_confirmed_at: "2026-08-28T01:02:00.000Z",
          completed_at: "2026-08-28T01:02:00.000Z",
        },
      });
    });
    pretender.get("/marketplace/listings/22", () =>
      response({ listing: this.listing })
    );

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
          @transactionsPagination={{this.pagination}}
        />
      </template>
    );

    assert.dom(".marketplace-transaction--pending").exists({ count: 2 });
    assert.dom(".marketplace-transaction--history").exists({ count: 1 });
    assert
      .dom('[data-transaction-id="101"] .marketplace-transaction__buyer')
      .includesText("buyer_a");
    assert
      .dom('[data-transaction-id="102"] .marketplace-transaction__buyer')
      .includesText("buyer_b");

    await click(
      '[data-transaction-id="101"] .marketplace-transaction__confirm'
    );

    assert.strictEqual(
      confirmedTransactionId,
      101,
      "the clicked row sends the exact transaction id"
    );
    assert
      .dom('[data-transaction-id="102"].marketplace-transaction--pending')
      .exists("the other buyer's transaction remains independently actionable");
  });

  test("buyer can repurchase after completion while the selected history transaction stays exact", async function (assert) {
    const sellerId = this.currentUser.id + 1;
    this.listing = {
      id: 23,
      title: "Repeatable download",
      status: "active",
      price_cents: 500,
      currency: "USD",
      cooked: "<p>Reusable purchase.</p>",
      inventory_mode: "unlimited",
      purchasable: true,
      expired: false,
      seller: { id: sellerId, username: "seller_user" },
    };
    this.transactions = [
      {
        id: 202,
        buyer_id: this.currentUser.id,
        seller_id: sellerId,
        status: "completed",
        buyer_confirmed_at: "2026-08-28T02:00:00.000Z",
        seller_confirmed_at: "2026-08-28T02:01:00.000Z",
        completed_at: "2026-08-28T02:01:00.000Z",
        buyer: { id: this.currentUser.id, username: this.currentUser.username },
      },
      {
        id: 201,
        buyer_id: this.currentUser.id,
        seller_id: sellerId,
        status: "completed",
        buyer_confirmed_at: "2026-08-27T02:00:00.000Z",
        seller_confirmed_at: "2026-08-27T02:01:00.000Z",
        completed_at: "2026-08-27T02:01:00.000Z",
        buyer: { id: this.currentUser.id, username: this.currentUser.username },
      },
    ];
    this.selectedTransactionId = 201;

    await render(
      <template>
        <MarketplaceListingDetail
          @listing={{this.listing}}
          @transactions={{this.transactions}}
          @selectedTransactionId={{this.selectedTransactionId}}
        />
      </template>
    );

    assert.dom("button.btn-primary").exists("Buy remains available");
    assert
      .dom('[data-transaction-id="201"].marketplace-transaction')
      .exists("the exact selected transaction owns the action/outlet region");
    assert
      .dom('[data-transaction-id="202"].marketplace-transaction')
      .doesNotExist("a different completed transaction is not substituted");
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
      this.transactions = [];

      await render(
        <template>
          <MarketplaceListingDetail
            @listing={{this.listing}}
            @transactions={{this.transactions}}
          />
        </template>
      );

      assert.dom(".marketplace-listing-detail__message-seller").doesNotExist();
    });
  }
);
