import { click, currentURL, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const SELLER = {
  id: 42,
  username: "seller",
  name: "Seller Name",
  avatar_template: "/user_avatar/test.local/seller/{size}/1.png",
};

function listing(id, title) {
  return {
    id,
    title,
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
    favorited: false,
    seller: SELLER,
    category: { id: 3, name: "Test", slug: "test" },
  };
}

const FIRST_LISTING = listing(77, "First seller listing");
const SECOND_LISTING = listing(78, "Second seller listing");

acceptance("Marketplace | seller storefront", function (needs) {
  needs.settings({ marketplace_enabled: true });
  needs.pretender((server, helper) => {
    server.get("/marketplace/categories", () =>
      helper.response({ categories: [] })
    );
    server.get("/marketplace/listings", () =>
      helper.response({
        listings: [FIRST_LISTING],
        pagination: { page: 1, per_page: 20, has_more: false },
      })
    );
    server.get("/marketplace/sellers/seller.json", (request) => {
      if (request.queryParams.page === "2") {
        return helper.response({
          seller: SELLER,
          listings: [SECOND_LISTING],
          pagination: { page: 2, per_page: 1, has_more: false },
        });
      }

      return helper.response({
        seller: SELLER,
        listings: [FIRST_LISTING],
        pagination: { page: 1, per_page: 1, has_more: true },
      });
    });
  });

  test("renders the seller identity and loads more listings", async function (assert) {
    await visit("/marketplace/sellers/seller");

    assert.strictEqual(currentURL(), "/marketplace/sellers/seller");
    assert.dom(".marketplace-storefront").exists();
    assert.dom(".marketplace-storefront__name").hasText("Seller Name");
    assert.dom(".marketplace-storefront__username").hasText("@seller");
    assert
      .dom(".marketplace-storefront__profile-link")
      .hasAttribute("href", "/u/seller");
    assert.dom(".marketplace-listing-card").exists({ count: 1 });
    assert.dom(".marketplace-storefront__load-more").exists();

    await click(".marketplace-storefront__load-more");

    assert.dom(".marketplace-listing-card").exists({ count: 2 });
    assert.dom(".marketplace-storefront__load-more").doesNotExist();
  });

  test("opens the storefront from a listing card", async function (assert) {
    await visit("/marketplace");

    assert.dom(".marketplace-listing-card__storefront").exists();
    await click(".marketplace-listing-card__storefront");

    assert.strictEqual(currentURL(), "/marketplace/sellers/seller");
    assert.dom(".marketplace-storefront").exists();
  });
});
