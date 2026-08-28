import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { concat } from "@ember/helper";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import PluginOutlet from "discourse/components/plugin-outlet";
import lazyHash from "discourse/helpers/lazy-hash";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class MarketplaceListingDetail extends Component {
  @service currentUser;
  @service composer;

  @tracked listing = this.args.listing;
  @tracked transaction = this.args.transaction;
  @tracked busy = false;
  @tracked errorMessage = null;

  get isSeller() {
    return this.currentUser?.id === this.listing.seller.id;
  }

  get formattedPrice() {
    return `${(this.listing.price_cents / 100).toFixed(2)} ${this.listing.currency}`;
  }

  get canBuy() {
    return (
      this.currentUser &&
      !this.isSeller &&
      !!this.listing.purchasable &&
      !this.transaction
    );
  }

  get canMessageSeller() {
    return this.currentUser && !this.isSeller && this.listing.seller;
  }

  // Only rendered while the listing is still active -- draft/reserved/sold/
  // archived already have their own dedicated status line above.
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

  get isParticipant() {
    return (
      this.transaction &&
      this.currentUser &&
      (this.currentUser.id === this.transaction.buyer_id ||
        this.currentUser.id === this.transaction.seller_id)
    );
  }

  get canConfirm() {
    if (!this.isParticipant || this.transaction.status !== "pending") {
      return false;
    }

    const isBuyer = this.currentUser.id === this.transaction.buyer_id;
    const alreadyConfirmed = isBuyer
      ? this.transaction.buyer_confirmed_at
      : this.transaction.seller_confirmed_at;
    return !alreadyConfirmed;
  }

  get canCancel() {
    return this.isParticipant && this.transaction.status === "pending";
  }

  async runAction(fn) {
    this.busy = true;
    this.errorMessage = null;
    try {
      await fn();
    } catch (error) {
      this.errorMessage =
        error.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("marketplace.transaction.error");
    } finally {
      this.busy = false;
    }
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

  // Re-fetches the listing rather than hand-patching status locally: a
  // finite/unlimited listing's availability (stock_available, purchasable)
  // can change without its status changing at all, so only the server's
  // view is trustworthy here.
  async refreshListing() {
    const result = await ajax(`/marketplace/listings/${this.listing.id}`);
    this.listing = result.listing;
  }

  @action
  buy() {
    this.runAction(async () => {
      const result = await ajax("/marketplace/transactions", {
        type: "POST",
        data: { listing_id: this.listing.id },
      });
      this.transaction = result.transaction;
      await this.refreshListing();
    });
  }

  @action
  confirm() {
    this.runAction(async () => {
      const result = await ajax(
        `/marketplace/transactions/${this.transaction.id}/confirm`,
        { type: "POST" }
      );
      this.transaction = result.transaction;
      if (result.transaction.status === "completed") {
        await this.refreshListing();
      }
    });
  }

  @action
  cancelTransaction() {
    this.runAction(async () => {
      const result = await ajax(
        `/marketplace/transactions/${this.transaction.id}/cancel`,
        { type: "POST" }
      );
      this.transaction = result.transaction;
      await this.refreshListing();
    });
  }

  @action
  publish() {
    this.runAction(async () => {
      const result = await ajax(`/marketplace/listings/${this.listing.id}/status`, {
        type: "PUT",
        data: { status: "active" },
      });
      this.listing = result.listing;
    });
  }

  @action
  archive() {
    this.runAction(async () => {
      const result = await ajax(`/marketplace/listings/${this.listing.id}/status`, {
        type: "PUT",
        data: { status: "archived" },
      });
      this.listing = result.listing;
    });
  }

  <template>
    <div class="marketplace-listing-detail">
      <div class="marketplace-listing-detail__layout">
        <div class="marketplace-listing-detail__content">
          {{#if this.listing.cooked}}
            <div class="marketplace-listing-detail__body">{{htmlSafe
                this.listing.cooked
              }}</div>
          {{/if}}
        </div>

        <div class="marketplace-listing-detail__panel">
          <span class="marketplace-listing-detail__status">{{i18n
              (concat "marketplace.listing.status." this.listing.status)
            }}</span>
          <h1 class="marketplace-listing-detail__title">{{this.listing.title}}</h1>
          <span class="marketplace-listing-detail__price">{{this.formattedPrice}}</span>
          {{#if this.availabilityLabel}}
            <span class="marketplace-listing-detail__availability">
              {{this.availabilityLabel}}
            </span>
          {{/if}}
          <span class="marketplace-listing-detail__seller">{{i18n
              "marketplace.listing.seller"
            }}
            {{this.listing.seller.username}}</span>

          {{#if this.errorMessage}}
            <div class="marketplace-listing-detail__error">{{this.errorMessage}}</div>
          {{/if}}

          <div class="marketplace-listing-detail__cta">
            {{#if this.isSeller}}
              <div class="marketplace-listing-detail__seller-actions">
                <LinkTo @route="marketplace.listing.edit" class="btn">
                  {{i18n "marketplace.listing.edit_button"}}
                </LinkTo>
                {{#if (eq this.listing.status "draft")}}
                  <button
                    type="button"
                    class="btn btn-primary"
                    disabled={{this.busy}}
                    {{on "click" this.publish}}
                  >{{i18n "marketplace.listing.publish_button"}}</button>
                {{/if}}
                {{#if (eq this.listing.status "active")}}
                  <button
                    type="button"
                    class="btn"
                    disabled={{this.busy}}
                    {{on "click" this.archive}}
                  >{{i18n "marketplace.listing.archive_button"}}</button>
                {{/if}}
              </div>
            {{else}}
              {{#if this.canMessageSeller}}
                <button
                  type="button"
                  class="btn marketplace-listing-detail__message-seller"
                  {{on "click" this.messageSeller}}
                >{{i18n "marketplace.listing.message_seller_button"}}</button>
              {{/if}}

              {{#if this.canBuy}}
                <button
                  type="button"
                  class="btn btn-primary"
                  disabled={{this.busy}}
                  {{on "click" this.buy}}
                >{{i18n "marketplace.listing.buy_button"}}</button>
              {{/if}}
            {{/if}}
          </div>

          {{#if this.transaction}}
            <div class="marketplace-transaction">
              <p>{{i18n
                  (concat "marketplace.transaction.status." this.transaction.status)
                }}</p>

              {{#if this.canConfirm}}
                <button
                  type="button"
                  class="btn btn-primary"
                  disabled={{this.busy}}
                  {{on "click" this.confirm}}
                >{{i18n "marketplace.transaction.confirm_button"}}</button>
              {{/if}}

              {{#if this.canCancel}}
                <button
                  type="button"
                  class="btn"
                  disabled={{this.busy}}
                  {{on "click" this.cancelTransaction}}
                >{{i18n "marketplace.transaction.cancel_button"}}</button>
              {{/if}}

              <PluginOutlet
                @name="marketplace-transaction-after-actions"
                @outletArgs={{lazyHash
                  listing=this.listing
                  transaction=this.transaction
                }}
                @defaultGlimmer={{true}}
              />
            </div>
          {{/if}}
        </div>
      </div>
    </div>
  </template>
}
