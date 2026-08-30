import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import PluginOutlet from "discourse/components/plugin-outlet";
import lazyHash from "discourse/helpers/lazy-hash";
import { ajax } from "discourse/lib/ajax";
import lightbox from "discourse/lib/lightbox";
import { and, eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class MarketplaceListingDetail extends Component {
  @service currentUser;
  @service composer;

  @tracked listing = this.args.listing;
  @tracked transactions = this.args.transactions || [];
  @tracked transactionsPagination = this.args.transactionsPagination;
  @tracked selectedTransactionId = this.args.selectedTransactionId;
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
      this.pendingTransactions.length === 0
    );
  }

  get canMessageSeller() {
    return this.currentUser && !this.isSeller && this.listing.seller;
  }

  get pendingTransactions() {
    return this.transactions.filter(
      (transaction) => transaction.status === "pending"
    );
  }

  get historyTransactions() {
    return this.transactions.filter(
      (transaction) => transaction.status !== "pending"
    );
  }

  get transaction() {
    if (this.selectedTransactionId) {
      const selected = this.transactions.find(
        (transaction) => transaction.id === this.selectedTransactionId
      );
      if (selected) {
        return selected;
      }
    }

    return this.pendingTransactions[0] || this.transactions[0] || null;
  }

  get hasMoreTransactions() {
    return !!this.transactionsPagination?.has_more;
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

  get customFields() {
    return (this.listing.custom_fields ?? []).map((field) => ({
      ...field,
      renderedValue:
        field.type === "boolean"
          ? i18n(
              field.value === "true"
                ? "marketplace.listing.boolean_yes"
                : "marketplace.listing.boolean_no"
            )
          : field.display_value,
    }));
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
    if (this.busy) {
      return;
    }

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
  setupLightbox(element) {
    lightbox(element);
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

  async refreshListing() {
    const result = await ajax(`/marketplace/listings/${this.listing.id}`);
    this.listing = result.listing;
  }

  replaceTransaction(updatedTransaction) {
    const existing = this.transactions.some(
      (transaction) => transaction.id === updatedTransaction.id
    );

    this.transactions = existing
      ? this.transactions.map((transaction) =>
          transaction.id === updatedTransaction.id
            ? updatedTransaction
            : transaction
        )
      : [updatedTransaction, ...this.transactions];
  }

  @action
  buy() {
    this.runAction(async () => {
      const result = await ajax("/marketplace/transactions", {
        type: "POST",
        data: { listing_id: this.listing.id },
      });
      this.replaceTransaction(result.transaction);
      this.selectedTransactionId = result.transaction.id;
      await this.refreshListing();
    });
  }

  @action
  confirm(transaction) {
    this.runAction(async () => {
      const result = await ajax(
        `/marketplace/transactions/${transaction.id}/confirm`,
        { type: "POST" }
      );
      this.replaceTransaction(result.transaction);
      this.selectedTransactionId = result.transaction.id;
      if (result.transaction.status === "completed") {
        await this.refreshListing();
      }
    });
  }

  @action
  cancelTransaction(transaction) {
    this.runAction(async () => {
      const result = await ajax(
        `/marketplace/transactions/${transaction.id}/cancel`,
        { type: "POST" }
      );
      this.replaceTransaction(result.transaction);
      this.selectedTransactionId = result.transaction.id;
      await this.refreshListing();
    });
  }

  @action
  loadMoreTransactions() {
    if (!this.hasMoreTransactions) {
      return;
    }

    this.runAction(async () => {
      const nextPage = this.transactionsPagination.page + 1;
      const result = await ajax(
        `/marketplace/listings/${this.listing.id}/transactions?page=${nextPage}&per_page=${this.transactionsPagination.per_page}`
      );
      const ids = new Set(this.transactions.map((transaction) => transaction.id));
      this.transactions = [
        ...this.transactions,
        ...result.transactions.filter((transaction) => !ids.has(transaction.id)),
      ];
      this.transactionsPagination = result.pagination;
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
    <main class="marketplace-listing-detail marketplace-page">
      <LinkTo
        @route="marketplace.index"
        class="marketplace-listing-detail__back"
      >
        {{dIcon "arrow-left"}}
        {{i18n "marketplace.listing.back_to_marketplace"}}
      </LinkTo>

      <div class="marketplace-listing-detail__layout">
        <div
          class="marketplace-listing-detail__content"
          {{didInsert this.setupLightbox}}
        >
          {{#if this.listing.thumbnail_url}}
            <a
              href={{this.listing.thumbnail_url}}
              class="lightbox marketplace-listing-detail__hero-link"
            >
              <img
                src={{this.listing.thumbnail_url}}
                alt={{this.listing.title}}
                class="marketplace-listing-detail__hero-image"
              />
            </a>
          {{/if}}

          {{#if this.customFields.length}}
            <section class="marketplace-listing-detail__specifications">
              <h2 class="marketplace-listing-detail__specifications-heading">
                {{i18n "marketplace.listing.details_heading"}}
              </h2>
              <dl class="marketplace-listing-detail__specification-grid">
                {{#each this.customFields as |field|}}
                  <div
                    class="marketplace-listing-detail__specification"
                    data-field-key={{field.key}}
                  >
                    <dt>{{field.label}}</dt>
                    <dd>{{field.renderedValue}}</dd>
                  </div>
                {{/each}}
              </dl>
            </section>
          {{/if}}

          {{#if this.listing.cooked}}
            <section class="marketplace-listing-detail__description">
              <h2 class="marketplace-listing-detail__description-heading">
                {{i18n "marketplace.listing.description_heading"}}
              </h2>
              <div class="marketplace-listing-detail__body">{{htmlSafe
                  this.listing.cooked
                }}</div>
            </section>
          {{/if}}
        </div>

        <div class="marketplace-listing-detail__panel">
          <div class="marketplace-listing-detail__badges">
            <span class="marketplace-listing-detail__status">{{i18n
                (concat "marketplace.listing.status." this.listing.status)
              }}</span>
            {{#if this.listing.category}}
              <span class="marketplace-listing-detail__category">
                {{this.listing.category.name}}
              </span>
            {{/if}}
          </div>
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
            <div class="marketplace-listing-detail__error" role="alert">
              {{this.errorMessage}}
            </div>
          {{/if}}

          <div class="marketplace-listing-detail__cta">
            {{#if this.isSeller}}
              <div class="marketplace-listing-detail__seller-actions">
                <LinkTo
                  @route="marketplace.listing.edit"
                  @model={{this.listing.id}}
                  class="btn marketplace-listing-detail__edit"
                >
                  {{i18n "marketplace.listing.edit_button"}}
                </LinkTo>
                {{#if (eq this.listing.status "draft")}}
                  <DButton
                    class="btn-primary"
                    @label="marketplace.listing.publish_button"
                    @action={{this.publish}}
                    @disabled={{this.busy}}
                    @isLoading={{this.busy}}
                  />
                {{/if}}
                {{#if (eq this.listing.status "active")}}
                  <DButton
                    @label="marketplace.listing.archive_button"
                    @action={{this.archive}}
                    @disabled={{this.busy}}
                    @isLoading={{this.busy}}
                  />
                {{/if}}
              </div>
            {{else}}
              {{#if this.canMessageSeller}}
                <DButton
                  class="marketplace-listing-detail__message-seller"
                  @label="marketplace.listing.message_seller_button"
                  @action={{this.messageSeller}}
                  @disabled={{this.busy}}
                />
              {{/if}}

              {{#if this.canBuy}}
                <DButton
                  class="btn-primary"
                  @label="marketplace.listing.buy_button"
                  @action={{this.buy}}
                  @disabled={{this.busy}}
                  @isLoading={{this.busy}}
                />
              {{/if}}
            {{/if}}
          </div>

          {{#if this.isSeller}}
            <section class="marketplace-transactions">
              <h2>{{i18n "marketplace.transaction.seller_heading"}}</h2>

              {{#if this.pendingTransactions.length}}
                <h3>{{i18n "marketplace.transaction.pending_heading"}}</h3>
                {{#each this.pendingTransactions as |transaction|}}
                  <article
                    class="marketplace-transaction marketplace-transaction--pending"
                    data-transaction-id={{transaction.id}}
                  >
                    <p class="marketplace-transaction__buyer">{{i18n
                        "marketplace.transaction.buyer"
                        username=transaction.buyer.username
                      }}</p>
                    <p>{{i18n
                        (concat "marketplace.transaction.status." transaction.status)
                      }}</p>

                    {{#if
                      (and
                        (eq transaction.status "pending")
                        (not transaction.seller_confirmed_at)
                      )
                    }}
                      <DButton
                        class="btn-primary marketplace-transaction__confirm"
                        @label="marketplace.transaction.confirm_button"
                        @action={{fn this.confirm transaction}}
                        @disabled={{this.busy}}
                        @isLoading={{this.busy}}
                      />
                    {{/if}}

                    {{#if (eq transaction.status "pending")}}
                      <DButton
                        class="marketplace-transaction__cancel"
                        @label="marketplace.transaction.cancel_button"
                        @action={{fn this.cancelTransaction transaction}}
                        @disabled={{this.busy}}
                      />
                    {{/if}}

                    <PluginOutlet
                      @name="marketplace-transaction-after-actions"
                      @outletArgs={{lazyHash
                        listing=this.listing
                        transaction=transaction
                      }}
                      @defaultGlimmer={{true}}
                    />
                  </article>
                {{/each}}
              {{else}}
                <p>{{i18n "marketplace.transaction.no_pending"}}</p>
              {{/if}}

              {{#if this.historyTransactions.length}}
                <h3>{{i18n "marketplace.transaction.history_heading"}}</h3>
                {{#each this.historyTransactions as |transaction|}}
                  <article
                    class="marketplace-transaction marketplace-transaction--history"
                    data-transaction-id={{transaction.id}}
                  >
                    <p class="marketplace-transaction__buyer">{{i18n
                        "marketplace.transaction.buyer"
                        username=transaction.buyer.username
                      }}</p>
                    <p>{{i18n
                        (concat "marketplace.transaction.status." transaction.status)
                      }}</p>

                    <PluginOutlet
                      @name="marketplace-transaction-after-actions"
                      @outletArgs={{lazyHash
                        listing=this.listing
                        transaction=transaction
                      }}
                      @defaultGlimmer={{true}}
                    />
                  </article>
                {{/each}}
              {{/if}}

              {{#if this.hasMoreTransactions}}
                <DButton
                  class="marketplace-transactions__load-more"
                  @label="marketplace.transaction.load_more"
                  @action={{this.loadMoreTransactions}}
                  @disabled={{this.busy}}
                  @isLoading={{this.busy}}
                />
              {{/if}}
            </section>
          {{else if this.transaction}}
            <div
              class="marketplace-transaction"
              data-transaction-id={{this.transaction.id}}
            >
              <p>{{i18n
                  (concat "marketplace.transaction.status." this.transaction.status)
                }}</p>

              {{#if this.canConfirm}}
                <DButton
                  class="btn-primary"
                  @label="marketplace.transaction.confirm_button"
                  @action={{fn this.confirm this.transaction}}
                  @disabled={{this.busy}}
                  @isLoading={{this.busy}}
                />
              {{/if}}

              {{#if this.canCancel}}
                <DButton
                  @label="marketplace.transaction.cancel_button"
                  @action={{fn this.cancelTransaction this.transaction}}
                  @disabled={{this.busy}}
                />
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
    </main>
  </template>
}
