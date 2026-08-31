import { click, select, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const EMPTY_LISTINGS = {
  listings: [],
  pagination: { page: 1, per_page: 20, has_more: false },
};

function transaction(overrides = {}) {
  return {
    id: 501,
    listing_id: 42,
    listing_title: "Mechanical keyboard",
    buyer_id: 9,
    seller_id: 7,
    status: "pending",
    buyer_confirmed_at: null,
    seller_confirmed_at: null,
    completed_at: null,
    cancelled_at: null,
    cancelled_by_id: null,
    created_at: "2026-08-28T12:00:00.000Z",
    updated_at: "2026-08-28T12:00:00.000Z",
    listing_title_snapshot: "Mechanical keyboard",
    price_cents_snapshot: 90000,
    currency_snapshot: "TRY",
    snapshot_captured: true,
    role: "buyer",
    listing_thumbnail_url: null,
    buyer: { id: 9, username: "buyer" },
    seller: { id: 7, username: "seller" },
    ...overrides,
  };
}

function page(transactions, pageNumber = 1, hasMore = false) {
  return {
    transactions,
    pagination: { page: pageNumber, per_page: 20, has_more: hasMore },
  };
}

acceptance("Marketplace | transaction center", function (needs) {
  let requests;
  let confirmRequests;

  needs.user({ id: 9, username: "buyer" });
  needs.settings({ marketplace_enabled: true });
  needs.pretender((server, helper) => {
    requests = [];
    confirmRequests = 0;

    server.get("/marketplace/categories", () =>
      helper.response({ categories: [] })
    );
    server.get("/marketplace/listings", () => helper.response(EMPTY_LISTINGS));
    server.get("/marketplace/transactions/mine", (request) => {
      const query = { ...request.queryParams };
      requests.push(query);

      if (query.role === "seller") {
        return helper.response(
          page([
            transaction({
              id: 502,
              listing_id: 43,
              listing_title: "Seller listing",
              listing_title_snapshot: "Seller listing",
              role: "seller",
              price_cents_snapshot: 120000,
            }),
          ])
        );
      }

      if (query.status === "completed") {
        return helper.response(
          page([
            transaction({
              id: 503,
              status: "completed",
              buyer_confirmed_at: "2026-08-29T12:00:00.000Z",
              seller_confirmed_at: "2026-08-29T12:00:00.000Z",
              completed_at: "2026-08-29T12:00:00.000Z",
            }),
          ])
        );
      }

      if (query.page === "2") {
        return helper.response(
          page(
            [
              transaction({
                id: 504,
                listing_id: 44,
                listing_title: "Second page listing",
                listing_title_snapshot: "Second page listing",
              }),
            ],
            2,
            false
          )
        );
      }

      return helper.response(page([transaction()], 1, true));
    });

    server.post("/marketplace/transactions/501/confirm", () => {
      confirmRequests += 1;
      return helper.response({
        transaction: {
          id: 501,
          status: "completed",
          buyer_confirmed_at: "2026-08-29T12:00:00.000Z",
          seller_confirmed_at: "2026-08-29T12:00:00.000Z",
          completed_at: "2026-08-29T12:00:00.000Z",
        },
      });
    });
  });

  test("renders buyer transactions and confirms without reloading", async function (assert) {
    await visit("/marketplace/transactions");

    assert.dom('[data-transaction-id="501"]').exists();
    assert
      .dom('[data-transaction-id="501"] .marketplace-transaction-center__title')
      .hasText("Mechanical keyboard");
    assert
      .dom('[data-transaction-id="501"] .marketplace-transaction-center__price')
      .hasText("900.00 TRY");
    assert
      .dom(".marketplace-transaction-center__tab:first-child")
      .hasAttribute("aria-pressed", "true");
    assert
      .dom(".marketplace-transaction-center__tab:nth-child(2)")
      .hasAttribute("aria-pressed", "false");
    assert.dom('[data-transaction-id="501"] .btn-primary').exists();

    await click('[data-transaction-id="501"] .btn-primary');

    assert.strictEqual(confirmRequests, 1);
    assert
      .dom(
        '[data-transaction-id="501"] .marketplace-transaction-center__status-badge'
      )
      .hasClass("marketplace-transaction-center__status-badge--completed");
    assert
      .dom(
        '[data-transaction-id="501"] .marketplace-transaction-center__actions'
      )
      .doesNotExist();
  });

  test("switches role and status filters through server-authoritative queries", async function (assert) {
    await visit("/marketplace/transactions");

    await click(".marketplace-transaction-center__tab:nth-child(2)");

    assert.strictEqual(requests.at(-1).role, "seller");
    assert.dom('[data-transaction-id="502"]').exists();
    assert
      .dom(".marketplace-transaction-center__tab:first-child")
      .hasAttribute("aria-pressed", "false");
    assert
      .dom(".marketplace-transaction-center__tab:nth-child(2)")
      .hasAttribute("aria-pressed", "true");

    await click(".marketplace-transaction-center__tab:first-child");
    await select(
      ".marketplace-transaction-center__filters select",
      "completed"
    );

    assert.strictEqual(requests.at(-1).role, "buyer");
    assert.strictEqual(requests.at(-1).status, "completed");
    assert.dom('[data-transaction-id="503"]').exists();
    assert
      .dom(
        '[data-transaction-id="503"] .marketplace-transaction-center__status-badge'
      )
      .hasClass("marketplace-transaction-center__status-badge--completed");
  });

  test("appends the next page and removes load more at the end", async function (assert) {
    await visit("/marketplace/transactions");

    assert.dom(".marketplace-transaction-center__card").exists({ count: 1 });
    assert.dom(".marketplace-transaction-center__load-more").exists();

    await click(".marketplace-transaction-center__load-more");

    assert.strictEqual(requests.at(-1).page, "2");
    assert.dom(".marketplace-transaction-center__card").exists({ count: 2 });
    assert.dom('[data-transaction-id="504"]').exists();
    assert.dom(".marketplace-transaction-center__load-more").doesNotExist();
  });
});
