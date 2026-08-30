import { click, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const CATEGORIES = [
  {
    id: 3,
    name: "Electronics",
    slug: "electronics",
    position: 0,
    field_definitions: [],
  },
  {
    id: 4,
    name: "Games",
    slug: "games",
    position: 1,
    field_definitions: [],
  },
];

function listing(id, category = CATEGORIES[0]) {
  return {
    id,
    title: `Listing ${id}`,
    status: "active",
    price_cents: id * 1000,
    currency: "USD",
    thumbnail_url: null,
    inventory_mode: "single",
    purchasable: true,
    expired: false,
    stock_available: null,
    favorited: false,
    category,
    seller: { id: 100 + id, username: `seller_${id}` },
  };
}

const LISTINGS = Array.from({ length: 6 }, (_, index) => listing(index + 1));

acceptance("Marketplace | showcase browse", function (needs) {
  let listingRequests;

  needs.settings({ marketplace_enabled: true });
  needs.pretender((server, helper) => {
    listingRequests = [];

    server.get("/marketplace/categories", () =>
      helper.response({ categories: CATEGORIES })
    );
    server.get("/marketplace/listings", (request) => {
      listingRequests.push({ ...request.queryParams });
      return helper.response({
        listings: LISTINGS,
        pagination: { page: 1, per_page: 20, has_more: false },
      });
    });
  });

  test("renders featured cards and a compact latest-listing section", async function (assert) {
    await visit("/marketplace");

    assert.dom(".marketplace-browse--showcase").exists();
    assert.dom(".marketplace-browse__category-card").exists({ count: 2 });
    assert
      .dom(".marketplace-browse__featured-grid .marketplace-listing-card")
      .exists({ count: 4 });
    assert
      .dom(".marketplace-browse__latest-list .marketplace-listing-card")
      .exists({ count: 2 });
  });

  test("filters from a category showcase card using the existing listing endpoint", async function (assert) {
    await visit("/marketplace");
    await click('[data-category-id="3"]');

    assert.strictEqual(listingRequests.at(-1).category_id, "3");
    assert
      .dom('[data-category-id="3"]')
      .hasClass("marketplace-browse__category-card--active");
  });
});
