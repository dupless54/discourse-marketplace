import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import MarketplaceListingCard from "./marketplace-listing-card";
import MarketplaceNav from "./marketplace-nav";

export default class MarketplaceMyListings extends Component {
  @tracked listings = this.args.initialListingsResult.listings;
  @tracked hasMore = this.args.initialListingsResult.pagination.has_more;
  @tracked page = this.args.initialListingsResult.pagination.page;
  @tracked loading = false;

  async fetchListings(page) {
    if (this.loading) {
      return;
    }

    this.loading = true;
    try {
      const result = await ajax("/marketplace/listings/mine", {
        data: { page },
      });

      this.listings =
        page === 1 ? result.listings : [...this.listings, ...result.listings];
      this.hasMore = result.pagination.has_more;
      this.page = result.pagination.page;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  loadMore() {
    this.fetchListings(this.page + 1);
  }

  <template>
    <main class="marketplace-my-listings marketplace-page">
      <MarketplaceNav />

      <header class="marketplace-page__header">
        <h1>{{i18n "marketplace.mine.title"}}</h1>
      </header>

      {{#if this.listings.length}}
        <div class="marketplace-listings-grid">
          {{#each this.listings as |listing|}}
            <MarketplaceListingCard @listing={{listing}} />
          {{/each}}
        </div>

        {{#if this.hasMore}}
          <div class="marketplace-page__load-more">
            <DButton
              class="marketplace-my-listings__load-more"
              @label="marketplace.mine.load_more"
              @action={{this.loadMore}}
              @disabled={{this.loading}}
              @isLoading={{this.loading}}
            />
          </div>
        {{/if}}
      {{else}}
        <div class="marketplace-page__empty" role="status">
          <p class="marketplace-my-listings__empty">{{i18n
              "marketplace.mine.empty"
            }}</p>
        </div>
      {{/if}}
    </main>
  </template>
}
