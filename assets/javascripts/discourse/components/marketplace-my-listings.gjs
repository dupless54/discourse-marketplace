import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { concat } from "@ember/helper";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

function formatPrice(cents, currency) {
  return `${(cents / 100).toFixed(2)} ${currency}`;
}

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
        <ul class="marketplace-my-listings__listings">
          {{#each this.listings as |listing|}}
            <li class="marketplace-listing-card">
              <LinkTo @route="marketplace.listing" @model={{listing.id}}>
                <span class="marketplace-listing-card__title">{{listing.title}}</span>
                <span class="marketplace-listing-card__status">{{i18n
                    (concat "marketplace.listing.status." listing.status)
                  }}</span>
                <span class="marketplace-listing-card__price">{{formatPrice
                    listing.price_cents
                    listing.currency
                  }}</span>
              </LinkTo>
            </li>
          {{/each}}
        </ul>

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
