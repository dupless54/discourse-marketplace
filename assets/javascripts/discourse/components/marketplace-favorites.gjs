import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import MarketplaceListingCard from "./marketplace-listing-card";
import MarketplaceNav from "./marketplace-nav";

export default class MarketplaceFavorites extends Component {
  @tracked listings = this.args.initialListingsResult.listings;
  @tracked hasMore = this.args.initialListingsResult.pagination.has_more;
  @tracked page = this.args.initialListingsResult.pagination.page;
  @tracked loading = false;

  async fetchListings(page) {
    this.loading = true;
    try {
      const result = await ajax("/marketplace/favorites", { data: { page } });
      this.listings =
        page === 1 ? result.listings : [...this.listings, ...result.listings];
      this.hasMore = result.pagination.has_more;
      this.page = result.pagination.page;
    } finally {
      this.loading = false;
    }
  }

  @action
  favoriteChanged(listingId, favorited) {
    if (!favorited) {
      this.listings = this.listings.filter((listing) => listing.id !== listingId);
    }
  }

  @action
  loadMore() {
    this.fetchListings(this.page + 1);
  }

  <template>
    <div class="marketplace-favorites">
      <MarketplaceNav />

      <h1>{{i18n "marketplace.favorites.title"}}</h1>

      {{#if this.listings.length}}
        <div class="marketplace-listings-grid">
          {{#each this.listings as |listing|}}
            <MarketplaceListingCard
              @listing={{listing}}
              @onFavoriteChange={{this.favoriteChanged}}
            />
          {{/each}}
        </div>

        {{#if this.hasMore}}
          <button
            type="button"
            class="btn marketplace-favorites__load-more"
            disabled={{this.loading}}
            {{on "click" this.loadMore}}
          >
            {{i18n "marketplace.favorites.load_more"}}
          </button>
        {{/if}}
      {{else}}
        <p class="marketplace-favorites__empty">{{i18n
            "marketplace.favorites.empty"
          }}</p>
      {{/if}}
    </div>
  </template>
}
