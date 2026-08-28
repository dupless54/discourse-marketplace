import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import MarketplaceListingCard from "./marketplace-listing-card";
import MarketplaceNav from "./marketplace-nav";

export default class MarketplaceBrowse extends Component {
  @tracked listings = this.args.initialListingsResult.listings;
  @tracked hasMore = this.args.initialListingsResult.pagination.has_more;
  @tracked page = this.args.initialListingsResult.pagination.page;
  @tracked loading = false;
  @tracked categoryId = "";
  @tracked query = "";
  @tracked sort = "newest";

  get sorts() {
    return [
      { value: "newest", label: i18n("marketplace.browse.sort_newest") },
      { value: "price_asc", label: i18n("marketplace.browse.sort_price_asc") },
      {
        value: "price_desc",
        label: i18n("marketplace.browse.sort_price_desc"),
      },
    ];
  }

  async fetchListings(page) {
    this.loading = true;
    try {
      const params = { page, sort: this.sort };
      if (this.categoryId) {
        params.category_id = this.categoryId;
      }
      if (this.query) {
        params.q = this.query;
      }

      const result = await ajax("/marketplace/listings", { data: params });

      this.listings =
        page === 1 ? result.listings : [...this.listings, ...result.listings];
      this.hasMore = result.pagination.has_more;
      this.page = result.pagination.page;
    } finally {
      this.loading = false;
    }
  }

  @action
  updateQuery(event) {
    this.query = event.target.value;
  }

  @action
  updateCategory(event) {
    this.categoryId = event.target.value;
    this.fetchListings(1);
  }

  @action
  updateSort(event) {
    this.sort = event.target.value;
    this.fetchListings(1);
  }

  @action
  search(event) {
    event.preventDefault();
    this.fetchListings(1);
  }

  @action
  loadMore() {
    this.fetchListings(this.page + 1);
  }

  <template>
    <div class="marketplace-browse">
      <MarketplaceNav />

      <div class="marketplace-browse__header">
        <h1>{{i18n "marketplace.title"}}</h1>
      </div>

      <form class="marketplace-browse__filters" {{on "submit" this.search}}>
        <input
          type="text"
          placeholder={{i18n "marketplace.browse.search_placeholder"}}
          value={{this.query}}
          {{on "input" this.updateQuery}}
        />

        <select {{on "change" this.updateCategory}}>
          <option value="">{{i18n "marketplace.browse.category_all"}}</option>
          {{#each @categories as |category|}}
            <option value={{category.id}}>{{category.name}}</option>
          {{/each}}
        </select>

        <select {{on "change" this.updateSort}}>
          {{#each this.sorts as |sortOption|}}
            <option value={{sortOption.value}}>{{sortOption.label}}</option>
          {{/each}}
        </select>

        <button type="submit" class="btn">{{i18n
            "marketplace.browse.search_button"
          }}</button>
      </form>

      {{#if this.listings.length}}
        <div class="marketplace-listings-grid">
          {{#each this.listings as |listing|}}
            <MarketplaceListingCard @listing={{listing}} />
          {{/each}}
        </div>

        {{#if this.hasMore}}
          <button
            type="button"
            class="btn marketplace-browse__load-more"
            disabled={{this.loading}}
            {{on "click" this.loadMore}}
          >
            {{i18n "marketplace.browse.load_more"}}
          </button>
        {{/if}}
      {{else}}
        <p class="marketplace-browse__empty">{{i18n "marketplace.browse.empty"}}</p>
      {{/if}}
    </div>
  </template>
}
