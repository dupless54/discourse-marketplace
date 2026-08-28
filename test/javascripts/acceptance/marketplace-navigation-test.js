import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const EMPTY_LISTINGS = {
  listings: [],
  pagination: { page: 1, per_page: 20, has_more: false },
};

const EMPTY_TRANSACTIONS = {
  transactions: [],
  pagination: { page: 1, per_page: 20, has_more: false },
};

function stubMarketplaceEndpoints(server, helper) {
  server.get("/marketplace/categories", () =>
    helper.response({ categories: [] })
  );
  server.get("/marketplace/listings", () => helper.response(EMPTY_LISTINGS));
  server.get("/marketplace/listings/mine", () =>
    helper.response(EMPTY_LISTINGS)
  );
  server.get("/marketplace/transactions/mine", () =>
    helper.response(EMPTY_TRANSACTIONS)
  );
}

function activeHref(assert) {
  const active = document.querySelectorAll(".marketplace-nav li.active");
  assert.strictEqual(active.length, 1, "exactly one nav item is active");
  return active[0].querySelector("a")?.getAttribute("href");
}

acceptance("Marketplace | navigation | anonymous", function (needs) {
  needs.settings({ marketplace_enabled: true });
  needs.pretender(stubMarketplaceEndpoints);

  test("shows only the Marketplace nav item, active, for an anonymous visitor", async function (assert) {
    await visit("/marketplace");

    assert.dom(".marketplace-nav").exists("the shared nav renders");
    assert
      .dom(".marketplace-nav li")
      .exists({ count: 1 }, "New Listing/My Listings/My Transactions are hidden");
    assert.strictEqual(activeHref(assert), "/marketplace");

    // Semantic structure: a real <nav> landmark with real links, not divs
    // wired up by hand.
    assert.dom("nav.horizontal-overflow-nav[aria-label]").exists();
    assert.dom(".marketplace-nav a").exists();
  });
});

acceptance("Marketplace | navigation | logged in", function (needs) {
  needs.user();
  needs.settings({ marketplace_enabled: true });
  needs.pretender(stubMarketplaceEndpoints);

  test("shows all four nav items with Marketplace active on /marketplace", async function (assert) {
    await visit("/marketplace");

    assert.dom(".marketplace-nav li").exists({ count: 4 });
    assert.strictEqual(activeHref(assert), "/marketplace");
  });

  test("marks New Listing active on /marketplace/new", async function (assert) {
    await visit("/marketplace/new");

    assert.strictEqual(activeHref(assert), "/marketplace/new");
  });

  test("marks My Listings active on /marketplace/mine", async function (assert) {
    await visit("/marketplace/mine");

    assert.strictEqual(activeHref(assert), "/marketplace/mine");
  });

  test("marks My Transactions active on /marketplace/transactions", async function (assert) {
    await visit("/marketplace/transactions");

    assert.strictEqual(activeHref(assert), "/marketplace/transactions");
  });
});
