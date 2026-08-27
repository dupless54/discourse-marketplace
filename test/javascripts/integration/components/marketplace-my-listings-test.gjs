import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import MarketplaceMyListings from "discourse/plugins/discourse-marketplace/discourse/components/marketplace-my-listings";

module("Integration | Component | MarketplaceMyListings", function (hooks) {
  setupRenderingTest(hooks);

  test("renders the current user's listings across every status", async function (assert) {
    this.initialListingsResult = {
      listings: [
        {
          id: 1,
          title: "Draft listing",
          status: "draft",
          price_cents: 1000,
          currency: "USD",
        },
        {
          id: 2,
          title: "Archived listing",
          status: "archived",
          price_cents: 2000,
          currency: "USD",
        },
      ],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceMyListings
          @initialListingsResult={{this.initialListingsResult}}
        />
      </template>
    );

    assert
      .dom(".marketplace-listing-card")
      .exists({ count: 2 }, "both of the seller's listings are rendered");
    assert
      .dom(".marketplace-my-listings__load-more")
      .doesNotExist("no load-more button when has_more is false");
  });

  test("shows the empty state and a load-more button when there are more pages", async function (assert) {
    this.emptyResult = {
      listings: [],
      pagination: { page: 1, per_page: 20, has_more: false },
    };

    await render(
      <template>
        <MarketplaceMyListings @initialListingsResult={{this.emptyResult}} />
      </template>
    );

    assert
      .dom(".marketplace-my-listings__empty")
      .exists("the empty state is shown when there are no listings");

    this.withMoreResult = {
      listings: [
        {
          id: 3,
          title: "Active listing",
          status: "active",
          price_cents: 500,
          currency: "USD",
        },
      ],
      pagination: { page: 1, per_page: 1, has_more: true },
    };

    await render(
      <template>
        <MarketplaceMyListings @initialListingsResult={{this.withMoreResult}} />
      </template>
    );

    assert
      .dom(".marketplace-my-listings__load-more")
      .exists("the load-more button is shown when has_more is true");
  });
});
