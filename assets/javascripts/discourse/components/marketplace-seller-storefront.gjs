import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import MarketplaceListingCard from "./marketplace-listing-card";
import MarketplaceNav from "./marketplace-nav";

export default class MarketplaceSellerStorefront extends Component {
  @tracked listings = this.args.initialResult.listings;
  @tracked pagination = this.args.initialResult.pagination;
  @tracked loading = false;

  get seller() {
    return this.args.initialResult.seller;
  }

  get displayName() {
    return this.seller.name || this.seller.username;
  }

  get avatarUrl() {
    return this.seller.avatar_template?.replace("{size}", "144");
  }

  get profileUrl() {
    return `/u/${encodeURIComponent(this.seller.username)}`;
  }

  @action
  async loadMore() {
    if (this.loading || !this.pagination.has_more) {
      return;
    }

    this.loading = true;
    try {
      const result = await ajax(
        `/marketplace/sellers/${encodeURIComponent(this.seller.username)}`,
        { data: { page: this.pagination.page + 1, per_page: this.pagination.per_page } }
      );
      const ids = new Set(this.listings.map((listing) => listing.id));
      this.listings = [
        ...this.listings,
        ...result.listings.filter((listing) => !ids.has(listing.id)),
      ];
      this.pagination = result.pagination;
    } finally {
      this.loading = false;
    }
  }

  <template>
    <div class="marketplace-storefront" data-seller-username={{this.seller.username}}>
      <MarketplaceNav />

      <LinkTo @route="marketplace.index" class="marketplace-storefront__back">
        {{i18n "marketplace.storefront.back"}}
      </LinkTo>

      <section class="marketplace-storefront__hero">
        {{#if this.avatarUrl}}
          <img
            class="marketplace-storefront__avatar"
            src={{this.avatarUrl}}
            alt={{this.displayName}}
            width="144"
            height="144"
          />
        {{/if}}

        <div class="marketplace-storefront__identity">
          <span class="marketplace-storefront__eyebrow">
            {{i18n "marketplace.storefront.eyebrow"}}
          </span>
          <h1 class="marketplace-storefront__name">{{this.displayName}}</h1>
          <span class="marketplace-storefront__username">@{{this.seller.username}}</span>
        </div>

        <a class="btn btn-default marketplace-storefront__profile-link" href={{this.profileUrl}}>
          {{i18n "marketplace.storefront.view_profile"}}
        </a>
      </section>

      <section class="marketplace-storefront__listings">
        <div class="marketplace-storefront__heading-row">
          <h2>{{i18n "marketplace.storefront.listings_title"}}</h2>
        </div>

        {{#if this.listings.length}}
          <div class="marketplace-listings-grid marketplace-storefront__grid">
            {{#each this.listings as |listing|}}
              <MarketplaceListingCard @listing={{listing}} />
            {{/each}}
          </div>

          {{#if this.pagination.has_more}}
            <button
              type="button"
              class="btn marketplace-storefront__load-more"
              disabled={{this.loading}}
              {{on "click" this.loadMore}}
            >
              {{i18n "marketplace.storefront.load_more"}}
            </button>
          {{/if}}
        {{else}}
          <p class="marketplace-storefront__empty">
            {{i18n "marketplace.storefront.empty"}}
          </p>
        {{/if}}
      </section>
    </div>
  </template>
}
