import { click, currentURL, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const CATEGORY = {
  id: 3,
  name: "Test",
  slug: "test",
  position: 0,
  field_definitions: [],
};

const LISTING = {
  id: 42,
  title: "Editable listing",
  category_id: CATEGORY.id,
  price_cents: 50000,
  currency: "TRY",
  status: "active",
  published_at: null,
  closed_at: null,
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
  category: {
    id: CATEGORY.id,
    name: CATEGORY.name,
    slug: CATEGORY.slug,
  },
  raw: "Original description",
  cooked: "<p>Original description</p>",
  can_edit: true,
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

function stubListingEditEndpoints(server, helper) {
  server.get("/marketplace/listings", () => helper.response(EMPTY_LISTINGS));
  server.get("/marketplace/listings/42", () =>
    helper.response({ listing: LISTING })
  );
  server.get("/marketplace/listings/42/transactions", () =>
    helper.response(EMPTY_TRANSACTIONS)
  );
  server.get("/marketplace/listings/42/offers", () =>
    helper.response(EMPTY_OFFERS)
  );
  server.get("/marketplace/categories", () =>
    helper.response({ categories: [CATEGORY] })
  );
}

acceptance("Marketplace | listing edit", function (needs) {
  needs.user({ id: 7, username: "seller" });
  needs.settings({
    marketplace_enabled: true,
    marketplace_allowed_currencies: "TRY|USD",
  });
  needs.pretender(stubListingEditEndpoints);

  test("opens the edit form from the seller listing detail", async function (assert) {
    await visit("/marketplace/listings/42");

    assert.dom(".marketplace-listing-detail").exists();
    assert.dom(".marketplace-listing-detail__edit").exists();

    await click(".marketplace-listing-detail__edit");

    assert.strictEqual(currentURL(), "/marketplace/listings/42/edit");
    assert.dom(".marketplace-listing-form").exists();
    assert.dom(".marketplace-listing-detail").doesNotExist();
    assert.dom(".marketplace-listing-form__category").hasValue("3");
  });

  test("renders the edit form when the edit URL is visited directly", async function (assert) {
    await visit("/marketplace/listings/42/edit");

    assert.strictEqual(currentURL(), "/marketplace/listings/42/edit");
    assert.dom(".marketplace-listing-form").exists();
    assert.dom(".marketplace-listing-detail").doesNotExist();
  });
});
