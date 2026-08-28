import { click, fillIn, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const LISTING = {
  id: 42,
  title: "Negotiable listing",
  category_id: 3,
  price_cents: 50000,
  currency: "TRY",
  status: "active",
  created_at: "2026-08-28T12:00:00.000Z",
  updated_at: "2026-08-28T12:00:00.000Z",
  inventory_mode: "unlimited",
  stock_quantity: null,
  stock_available: null,
  stock_sold: 0,
  expires_at: null,
  expired: false,
  purchasable: true,
  seller: {
    id: 7,
    username: "seller",
    name: "Seller",
    avatar_template: "/letter_avatar_proxy/v4/letter/s/abcdef/{size}.png",
  },
  category: { id: 3, name: "Test", slug: "test" },
  raw: "Description",
  cooked: "<p>Description</p>",
  can_edit: false,
  custom_fields: [],
};

const EMPTY_LISTINGS = {
  listings: [],
  pagination: { page: 1, per_page: 20, has_more: false },
};
const EMPTY_TRANSACTIONS = {
  transactions: [],
  pagination: { page: 1, per_page: 20, has_more: false },
};
const EMPTY_OFFERS = {
  offers: [],
  pagination: { page: 1, per_page: 50, has_more: false },
};

function offer(overrides = {}) {
  return {
    id: 88,
    listing_id: 42,
    listing_title: LISTING.title,
    listing_status: "active",
    asking_price_cents: 50000,
    buyer_id: 9,
    seller_id: 7,
    proposed_by_id: 9,
    responded_by_id: null,
    status: "pending",
    amount_cents: 45000,
    currency: "TRY",
    expires_at: "2026-08-30T12:00:00.000Z",
    responded_at: null,
    accepted_transaction_id: null,
    created_at: "2026-08-28T12:00:00.000Z",
    updated_at: "2026-08-28T12:00:00.000Z",
    buyer: { id: 9, username: "buyer" },
    seller: { id: 7, username: "seller" },
    ...overrides,
  };
}

function stubListing(server, helper) {
  server.get("/marketplace/listings", () => helper.response(EMPTY_LISTINGS));
  server.get("/marketplace/listings/42", () =>
    helper.response({ listing: LISTING })
  );
  server.get("/marketplace/listings/42/transactions", () =>
    helper.response(EMPTY_TRANSACTIONS)
  );
}

acceptance("Marketplace | offers | buyer", function (needs) {
  needs.user({ id: 9, username: "buyer" });
  needs.settings({ marketplace_enabled: true });
  needs.pretender((server, helper) => {
    stubListing(server, helper);
    server.get("/marketplace/listings/42/offers", () => helper.response(EMPTY_OFFERS));
    server.post("/marketplace/offers", () => helper.response({ offer: offer() }));
  });

  test("creates an offer from the listing without a page reload", async function (assert) {
    await visit("/marketplace/listings/42");

    assert.dom(".marketplace-offer-panel").exists();
    assert.dom(".marketplace-offer-panel__new input").exists();

    await fillIn(".marketplace-offer-panel__new input", "450");
    await click(".marketplace-offer-panel__new .btn-primary");

    assert.dom(".marketplace-offer-panel__item").exists({ count: 1 });
    assert.dom(".marketplace-offer-panel__price").hasText("450.00 TRY");
    assert.dom(".marketplace-offer-panel__item .btn").hasText("Withdraw");
  });
});

acceptance("Marketplace | offers | seller", function (needs) {
  needs.user({ id: 7, username: "seller" });
  needs.settings({ marketplace_enabled: true });
  needs.pretender((server, helper) => {
    stubListing(server, helper);
    server.get("/marketplace/listings/42/offers", () =>
      helper.response({ offers: [offer()], pagination: EMPTY_OFFERS.pagination })
    );
    server.post("/marketplace/offers/88/counter", () =>
      helper.response({
        offer: offer({ amount_cents: 47500, proposed_by_id: 7 }),
      })
    );
  });

  test("lets the seller send a counteroffer from the listing", async function (assert) {
    await visit("/marketplace/listings/42");

    assert.dom(".marketplace-offer-panel__price").hasText("450.00 TRY");
    await click(".marketplace-offer-panel__actions .btn:nth-child(3)");
    await fillIn(".marketplace-offer-panel__counter input", "475");
    await click(".marketplace-offer-panel__counter .btn-primary");

    assert.dom(".marketplace-offer-panel__price").hasText("475.00 TRY");
    assert.dom(".marketplace-offer-panel__counter").doesNotExist();
  });
});
