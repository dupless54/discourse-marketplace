import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import MarketplaceTransactionCenter from "discourse/plugins/discourse-marketplace/discourse/components/marketplace-transaction-center";

module("Integration | Component | MarketplaceTransactionCenter", function (hooks) {
  setupRenderingTest(hooks);

  function pendingTransaction(overrides = {}) {
    return {
      id: 1,
      listing_id: 10,
      role: "buyer",
      status: "pending",
      listing_title_snapshot: "Ürün A",
      price_cents_snapshot: 10000,
      currency_snapshot: "USD",
      listing_thumbnail_url: null,
      buyer_confirmed_at: null,
      seller_confirmed_at: null,
      completed_at: null,
      cancelled_at: null,
      created_at: "2026-01-01T00:00:00.000Z",
      buyer: { id: 5, username: "buyerbob" },
      seller: { id: 6, username: "sellersam" },
      ...overrides,
    };
  }

  test("renders transaction cards using the immutable snapshot fields, not any live listing data", async function (assert) {
    this.initialResult = {
      transactions: [pendingTransaction()],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceTransactionCenter
          @initialRole="buyer"
          @initialResult={{this.initialResult}}
        />
      </template>
    );

    assert.dom(".marketplace-transaction-center__card").exists({ count: 1 });
    assert
      .dom(".marketplace-transaction-center__title")
      .hasText("Ürün A", "renders the snapshot title");
    assert
      .dom(".marketplace-transaction-center__price")
      .hasText("100.00 USD", "renders the snapshot price/currency");
  });

  test("shows the empty state when there are no transactions", async function (assert) {
    this.initialResult = {
      transactions: [],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceTransactionCenter
          @initialRole="buyer"
          @initialResult={{this.initialResult}}
        />
      </template>
    );

    assert.dom(".marketplace-transaction-center__empty").exists();
    assert.dom(".marketplace-transaction-center__card").doesNotExist();
  });

  test("shows a load-more button when has_more is true", async function (assert) {
    this.initialResult = {
      transactions: [pendingTransaction()],
      pagination: { page: 1, per_page: 1, has_more: true },
    };

    await render(
      <template>
        <MarketplaceTransactionCenter
          @initialRole="buyer"
          @initialResult={{this.initialResult}}
        />
      </template>
    );

    assert.dom(".marketplace-transaction-center__load-more").exists();
  });

  test("shows Confirm and Cancel for a pending transaction awaiting the viewer's own confirmation", async function (assert) {
    this.initialResult = {
      transactions: [pendingTransaction()],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceTransactionCenter
          @initialRole="buyer"
          @initialResult={{this.initialResult}}
        />
      </template>
    );

    assert.dom(".marketplace-transaction-center__actions .btn-primary").exists("Confirm is shown");
    assert.dom(".marketplace-transaction-center__actions .btn").exists("Cancel is shown");
  });

  test("hides Confirm once the viewer's own side already confirmed", async function (assert) {
    this.initialResult = {
      transactions: [pendingTransaction({ buyer_confirmed_at: "2026-01-01T00:00:00.000Z" })],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceTransactionCenter
          @initialRole="buyer"
          @initialResult={{this.initialResult}}
        />
      </template>
    );

    assert.dom(".marketplace-transaction-center__actions .btn-primary").doesNotExist();
  });

  test("hides all actions for a completed transaction", async function (assert) {
    this.initialResult = {
      transactions: [
        pendingTransaction({
          status: "completed",
          buyer_confirmed_at: "2026-01-01T00:00:00.000Z",
          seller_confirmed_at: "2026-01-01T00:00:00.000Z",
          completed_at: "2026-01-01T00:00:00.000Z",
        }),
      ],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceTransactionCenter
          @initialRole="buyer"
          @initialResult={{this.initialResult}}
        />
      </template>
    );

    assert.dom(".marketplace-transaction-center__actions").doesNotExist();
  });

  test("links each card to the exact listing/transaction via a transaction_id query param", async function (assert) {
    this.initialResult = {
      transactions: [pendingTransaction()],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceTransactionCenter
          @initialRole="buyer"
          @initialResult={{this.initialResult}}
        />
      </template>
    );

    const href = document
      .querySelector(".marketplace-transaction-center__card-link")
      .getAttribute("href");

    assert.true(href.includes("/marketplace/listings/10"), "links to the exact listing");
    assert.true(href.includes("transaction_id=1"), "carries the exact transaction id");
  });

  test("renders both role tabs", async function (assert) {
    this.initialResult = {
      transactions: [],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceTransactionCenter
          @initialRole="buyer"
          @initialResult={{this.initialResult}}
        />
      </template>
    );

    assert
      .dom(".marketplace-transaction-center__tab")
      .exists({ count: 2 }, "renders the buyer and seller tabs");
  });
});
