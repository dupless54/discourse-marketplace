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
      this.listing.status === "active" &&
      !this.transaction
    );
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
  buy() {
    this.runAction(async () => {
      const result = await ajax("/marketplace/transactions", {
        type: "POST",
        data: { listing_id: this.listing.id },
      });
      this.transaction = result.transaction;
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
        this.listing = { ...this.listing, status: "sold" };
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
      this.listing = { ...this.listing, status: "active" };
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
      <h1>{{this.listing.title}}</h1>
      <div class="marketplace-listing-detail__meta">
        <span class="marketplace-listing-detail__status">{{i18n
            (concat "marketplace.listing.status." this.listing.status)
          }}</span>
        <span class="marketplace-listing-detail__price">{{this.formattedPrice}}</span>
        <span class="marketplace-listing-detail__seller">{{i18n
            "marketplace.listing.seller"
          }}
          {{this.listing.seller.username}}</span>
      </div>

      {{#if this.listing.cooked}}
        <div class="marketplace-listing-detail__body">{{htmlSafe
            this.listing.cooked
          }}</div>
      {{/if}}

      {{#if this.errorMessage}}
        <div class="marketplace-listing-detail__error">{{this.errorMessage}}</div>
      {{/if}}

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
      {{/if}}

      {{#if this.canBuy}}
        <button
          type="button"
          class="btn btn-primary"
          disabled={{this.busy}}
          {{on "click" this.buy}}
        >{{i18n "marketplace.listing.buy_button"}}</button>
      {{/if}}

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
  </template>
}
