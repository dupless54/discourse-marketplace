import { click, currentURL, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const EMPTY_LISTINGS = {
  listings: [],
  pagination: { page: 1, per_page: 20, has_more: false },
};

const LISTING = {
  id: 77,
  title: "Saved marketplace listing",
  category_id: 3,
  price_cents: 12500,
  currency: "USD",
  status: "active",
  published_at: "2026-08-28T12:00:00.000Z",
  thumbnail_url: null,
  inventory_mode: "single",
  stock_quantity: null,
  stock_available: null,
  stock_sold: 0,
  expires_at: null,
  expired: false,
  purchasable: true,
  favorited: true,
  seller: { id: 42, username: "seller" },
  category: { id: 3, name: "Test", slug: "test" },
};

acceptance("Marketplace | favorites", function (needs) {
  needs.user({ id: 7, username: "buyer" });
  needs.settings({ marketplace_enabled: true });
  needs.pretender((server, helper) => {
    // The Marketplace parent route may settle through the browse index while
    // Ember enters this child route directly, so keep those parent requests
    // deterministic in the acceptance environment as well.
    server.get("/marketplace/categories", () =>
      helper.response({ categories: [] })
    );
    server.get("/marketplace/listings", () => helper.response(EMPTY_LISTINGS));
    server.get("/marketplace/favorites", () =>
      helper.response({
        listings: [LISTING],
        pagination: { page: 1, per_page: 20, has_more: false },
      })
    );
    server.delete("/marketplace/listings/77/favorite", () =>
      helper.response({ favorited: false })
    );
  });

  test("shows saved listings and removes them without a page reload", async function (assert) {
    await visit("/marketplace/favorites");

    assert.strictEqual(currentURL(), "/marketplace/favorites");
    assert.dom(".marketplace-favorites").exists();
    assert.dom(".marketplace-listing-card").exists({ count: 1 });
    assert
      .dom(".marketplace-listing-card__favorite")
      .hasText("Remove from Favorites");

    await click(".marketplace-listing-card__favorite");

    assert.dom(".marketplace-listing-card").doesNotExist();
    assert
      .dom(".marketplace-favorites__empty")
      .hasText("You haven't saved any listings yet.");
  });
});
