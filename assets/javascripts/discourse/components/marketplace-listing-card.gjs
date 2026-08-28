import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

function formatPrice(cents, currency) {
  return `${(cents / 100).toFixed(2)} ${currency}`;
}

export default class MarketplaceListingCard extends Component {
  @service currentUser;
  @service composer;

  @tracked favorited = !!this.args.listing.favorited;
  @tracked favoriteBusy = false;
  @tracked favoriteError = null;

  get listing() {
    return this.args.listing;
  }

  get isSeller() {
    return !!(
      this.currentUser &&
      this.listing.seller &&
      this.currentUser.id === this.listing.seller.id
    );
  }

  get canBuy() {
    return !!this.currentUser && !this.isSeller && !!this.listing.purchasable;
  }

  get canMessageSeller() {
    return !!this.currentUser && !this.isSeller && this.listing.seller;
  }

  get formattedPrice() {
    return formatPrice(this.listing.price_cents, this.listing.currency);
  }

  get statusLabel() {
    return i18n(`marketplace.listing.status.${this.listing.status}`);
  }

  get favoriteLabel() {
    return i18n(
      this.favorited
        ? "marketplace.favorites.remove"
        : "marketplace.favorites.add"
    );
  }

  get availabilityLabel() {
    if (this.listing.status !== "active") {
      return null;
    }
    if (this.listing.expired) {
      return i18n("marketplace.listing.expires.expired");
    }
    if (this.listing.inventory_mode === "unlimited") {
      return i18n("marketplace.listing.stock.unlimited");
    }
    if (this.listing.inventory_mode === "finite") {
      return this.listing.stock_available > 0
        ? i18n("marketplace.listing.stock.remaining", {
            count: this.listing.stock_available,
          })
        : i18n("marketplace.listing.stock.out_of_stock");
    }
    return null;
  }

  @action
  messageSeller() {
    this.composer.openNewMessage({
      recipients: this.listing.seller.username,
      title: i18n("marketplace.listing.message_seller_subject", {
        listing_title: this.listing.title,
      }),
    });
  }

  @action
  async toggleFavorite() {
    if (this.favoriteBusy) {
      return;
    }

    this.favoriteBusy = true;
    this.favoriteError = null;
    try {
      const result = await ajax(
        `/marketplace/listings/${this.listing.id}/favorite`,
        { type: this.favorited ? "DELETE" : "POST" }
      );
      this.favorited = !!result.favorited;
      this.listing.favorited = this.favorited;
      this.args.onFavoriteChange?.(this.listing.id, this.favorited);
    } catch (_error) {
      this.favoriteError = i18n("marketplace.favorites.error");
    } finally {
      this.favoriteBusy = false;
    }
  }

  <template>
    <div class="marketplace-listing-card">
      <LinkTo
        @route="marketplace.listing"
        @model={{this.listing.id}}
        class="marketplace-listing-card__media-link"
      >
        <span class="marketplace-listing-card__media">
          {{#if this.listing.thumbnail_url}}
            <img
              src={{this.listing.thumbnail_url}}
              alt={{this.listing.title}}
              loading="lazy"
              class="marketplace-listing-card__image"
            />
          {{else}}
            <span class="marketplace-listing-card__placeholder">
              {{dIcon "image"}}
            </span>
          {{/if}}
          {{#if this.listing.category}}
            <span class="marketplace-listing-card__category-badge">
              {{this.listing.category.name}}
            </span>
          {{/if}}
          <span
            class={{concat
              "marketplace-listing-card__status-badge marketplace-listing-card__status-badge--"
              this.listing.status
            }}
          >{{this.statusLabel}}</span>
        </span>

        <span class="marketplace-listing-card__body">
          <span class="marketplace-listing-card__price">{{this.formattedPrice}}</span>
          <span class="marketplace-listing-card__title">{{this.listing.title}}</span>
          {{#if this.availabilityLabel}}
            <span class="marketplace-listing-card__availability">
              {{this.availabilityLabel}}
            </span>
          {{/if}}
          {{#if this.listing.seller}}
            <span class="marketplace-listing-card__seller">{{i18n
                "marketplace.listing.seller"
              }}
              {{this.listing.seller.username}}</span>
          {{/if}}
        </span>
      </LinkTo>

      <span class="marketplace-listing-card__actions">
        {{#if this.currentUser}}
          <button
            type="button"
            class="btn btn-default btn-small marketplace-listing-card__favorite"
            aria-pressed={{this.favorited}}
            disabled={{this.favoriteBusy}}
            {{on "click" this.toggleFavorite}}
          >
            {{dIcon "heart"}}
            {{this.favoriteLabel}}
          </button>
        {{/if}}

        {{#if this.isSeller}}
          <LinkTo
            @route="marketplace.listing.edit"
            @model={{this.listing.id}}
            class="btn btn-default btn-small marketplace-listing-card__edit"
          >
            {{i18n "marketplace.listing.edit_button"}}
          </LinkTo>
        {{else}}
          {{#if this.canMessageSeller}}
            <button
              type="button"
              class="btn btn-default btn-small marketplace-listing-card__message"
              {{on "click" this.messageSeller}}
            >
              {{i18n "marketplace.listing.message_seller_button"}}
            </button>
          {{/if}}
          {{#if this.canBuy}}
            <LinkTo
              @route="marketplace.listing"
              @model={{this.listing.id}}
              class="btn btn-primary btn-small marketplace-listing-card__buy"
            >
              {{i18n "marketplace.listing.buy_button"}}
            </LinkTo>
          {{/if}}
        {{/if}}
      </span>
      {{#if this.favoriteError}}
        <span class="marketplace-listing-card__favorite-error">{{this.favoriteError}}</span>
      {{/if}}
    </div>
  </template>
}
