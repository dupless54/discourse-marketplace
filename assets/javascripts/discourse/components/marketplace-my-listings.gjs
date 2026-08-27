import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import MarketplaceListingCard from "./marketplace-listing-card";

export default class MarketplaceMyListings extends Component {
  @tracked listings = this.args.initialListingsResult.listings;
  @tracked hasMore = this.args.initialListingsResult.pagination.has_more;
  @tracked page = this.args.initialListingsResult.pagination.page;
  @tracked loading = false;

  async fetchListings(page) {
    this.loading = true;
    try {
      const result = await ajax("/marketplace/listings/mine", {
        data: { page },
      });

      this.listings =
        page === 1 ? result.listings : [...this.listings, ...result.listings];
      this.hasMore = result.pagination.has_more;
      this.page = result.pagination.page;
    } finally {
      this.loading = false;
    }
  }

  @action
  loadMore() {
    this.fetchListings(this.page + 1);
  }

  <template>
    <div class="marketplace-my-listings">
      <h1>{{i18n "marketplace.mine.title"}}</h1>

      {{#if this.listings.length}}
        <div class="marketplace-listings-grid">
          {{#each this.listings as |listing|}}
            <MarketplaceListingCard @listing={{listing}} />
          {{/each}}
        </div>

        {{#if this.hasMore}}
          <button
            type="button"
            class="btn marketplace-my-listings__load-more"
            disabled={{this.loading}}
            {{on "click" this.loadMore}}
          >
            {{i18n "marketplace.mine.load_more"}}
          </button>
        {{/if}}
      {{else}}
        <p class="marketplace-my-listings__empty">{{i18n "marketplace.mine.empty"}}</p>
      {{/if}}
    </div>
  </template>
}
