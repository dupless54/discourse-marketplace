import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { concat, fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import PluginOutlet from "discourse/components/plugin-outlet";
import lazyHash from "discourse/helpers/lazy-hash";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ROLES = ["buyer", "seller"];
const STATUSES = ["all", "pending", "completed", "cancelled"];

function formatPrice(cents, currency) {
  return `${(cents / 100).toFixed(2)} ${currency}`;
}

function relevantDate(transaction) {
  return (
    transaction.completed_at || transaction.cancelled_at || transaction.created_at
  );
}

function formatDate(iso) {
  if (!iso) {
    return "";
  }
  return new Date(iso).toLocaleDateString();
}

// Builds the per-card view model once per response rather than computing
// derived fields (canConfirm/canCancel/formatted price/dates) inline from
// the template -- Glimmer templates in this codebase only invoke plain
// helpers/getters, never a bound method with the loop item as an argument
// (see marketplace-listing-detail.gjs / marketplace-listing-card.gjs), so
// anything item-specific is precomputed here instead.
function toViewModel(transaction) {
  const isBuyer = transaction.role === "buyer";
  const counterparty = isBuyer ? transaction.seller : transaction.buyer;
  const alreadyConfirmed = isBuyer
    ? transaction.buyer_confirmed_at
    : transaction.seller_confirmed_at;

  return {
    transaction,
    id: transaction.id,
    listingId: transaction.listing_id,
    role: transaction.role,
    title: transaction.listing_title_snapshot,
    thumbnailUrl: transaction.listing_thumbnail_url,
    price: formatPrice(
      transaction.price_cents_snapshot,
      transaction.currency_snapshot
    ),
    status: transaction.status,
    counterpartyUsername: counterparty?.username,
    dateLabel: formatDate(relevantDate(transaction)),
    canConfirm: transaction.status === "pending" && !alreadyConfirmed,
    canCancel: transaction.status === "pending",
  };
}

export default class MarketplaceTransactionCenter extends Component {
  @tracked role = this.args.initialRole || "buyer";
  @tracked status = "all";
  @tracked transactions = this.args.initialResult.transactions;
  @tracked hasMore = this.args.initialResult.pagination.has_more;
  @tracked page = this.args.initialResult.pagination.page;
  @tracked loading = false;
  @tracked errorMessage = null;
  @tracked busyTransactionId = null;

  get roleTabs() {
    return ROLES.map((value) => ({
      value,
      label: i18n(`marketplace.transactions.tabs.${value}`),
      active: value === this.role,
    }));
  }

  get statusFilters() {
    return STATUSES.map((value) => ({
      value,
      label:
        value === "all"
          ? i18n("marketplace.transactions.filters.all")
          : i18n(`marketplace.transaction.status.${value}`),
    }));
  }

  get transactionViewModels() {
    return this.transactions.map(toViewModel);
  }

  async fetchTransactions(page) {
    this.loading = true;
    this.errorMessage = null;
    try {
      const params = { role: this.role, page };
      if (this.status !== "all") {
        params.status = this.status;
      }

      const result = await ajax("/marketplace/transactions/mine", {
        data: params,
      });

      this.transactions =
        page === 1
          ? result.transactions
          : [...this.transactions, ...result.transactions];
      this.hasMore = result.pagination.has_more;
      this.page = result.pagination.page;
    } catch {
      this.errorMessage = i18n("marketplace.transaction.error");
    } finally {
      this.loading = false;
    }
  }

  @action
  selectTab(role) {
    if (this.role === role) {
      return;
    }
    this.role = role;
    this.fetchTransactions(1);
  }

  @action
  selectStatus(event) {
    this.status = event.target.value;
    this.fetchTransactions(1);
  }

  @action
  loadMore() {
    this.fetchTransactions(this.page + 1);
  }

  // #confirm/#cancel respond with the plain TransactionSerializer shape
  // (no `role`/`listing_thumbnail_url` -- those are Transaction Center-only
  // additions on TransactionSummarySerializer), so the old view's fields
  // are spread first and only overwritten by whatever the response
  // actually included.
  replaceTransaction(updated) {
    this.transactions = this.transactions.map((transaction) =>
      transaction.id === updated.id
        ? { ...transaction, ...updated }
        : transaction
    );
  }

  async runAction(transactionId, fn) {
    this.busyTransactionId = transactionId;
    this.errorMessage = null;
    try {
      await fn();
    } catch (error) {
      this.errorMessage =
        error.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("marketplace.transaction.error");
    } finally {
      this.busyTransactionId = null;
    }
  }

  @action
  confirm(item) {
    this.runAction(item.id, async () => {
      const result = await ajax(
        `/marketplace/transactions/${item.id}/confirm`,
        { type: "POST" }
      );
      this.replaceTransaction(result.transaction);
    });
  }

  @action
  cancelTransaction(item) {
    this.runAction(item.id, async () => {
      const result = await ajax(
        `/marketplace/transactions/${item.id}/cancel`,
        { type: "POST" }
      );
      this.replaceTransaction(result.transaction);
    });
  }

  <template>
    <div class="marketplace-transaction-center">
      <h1>{{i18n "marketplace.transactions.title"}}</h1>

      <div class="marketplace-transaction-center__tabs">
        {{#each this.roleTabs as |tab|}}
          <button
            type="button"
            class={{concat
              "btn marketplace-transaction-center__tab"
              (if tab.active " marketplace-transaction-center__tab--active" "")
            }}
            disabled={{this.loading}}
            {{on "click" (fn this.selectTab tab.value)}}
          >
            {{tab.label}}
          </button>
        {{/each}}
      </div>

      <div class="marketplace-transaction-center__filters">
        <select {{on "change" this.selectStatus}}>
          {{#each this.statusFilters as |filter|}}
            <option value={{filter.value}}>{{filter.label}}</option>
          {{/each}}
        </select>
      </div>

      {{#if this.errorMessage}}
        <div class="marketplace-transaction-center__error">
          {{this.errorMessage}}
        </div>
      {{/if}}

      {{#if this.transactionViewModels.length}}
        <div class="marketplace-transaction-center__list">
          {{#each this.transactionViewModels as |item|}}
            <article
              class="marketplace-transaction-center__card"
              data-transaction-id={{item.id}}
            >
              <LinkTo
                @route="marketplace.listing"
                @model={{item.listingId}}
                @query={{hash transaction_id=item.id}}
                class="marketplace-transaction-center__card-link"
              >
                <span class="marketplace-transaction-center__media">
                  {{#if item.thumbnailUrl}}
                    <img
                      src={{item.thumbnailUrl}}
                      alt={{item.title}}
                      loading="lazy"
                      class="marketplace-transaction-center__image"
                    />
                  {{else}}
                    <span class="marketplace-transaction-center__placeholder">
                      {{dIcon "image"}}
                    </span>
                  {{/if}}
                </span>

                <span class="marketplace-transaction-center__body">
                  <span class="marketplace-transaction-center__title">
                    {{item.title}}
                  </span>
                  <span class="marketplace-transaction-center__price">
                    {{item.price}}
                  </span>
                  <span
                    class={{concat
                      "marketplace-transaction-center__status-badge marketplace-transaction-center__status-badge--"
                      item.status
                    }}
                  >
                    {{i18n (concat "marketplace.transaction.status." item.status)}}
                  </span>
                  <span class="marketplace-transaction-center__counterparty">
                    {{#if (eq item.role "buyer")}}
                      {{i18n "marketplace.listing.seller"}}
                      {{item.counterpartyUsername}}
                    {{else}}
                      {{i18n "marketplace.transaction.buyer" username=item.counterpartyUsername}}
                    {{/if}}
                  </span>
                  <span class="marketplace-transaction-center__date">
                    {{item.dateLabel}}
                  </span>
                </span>
              </LinkTo>

              {{#if (eq item.status "pending")}}
                <div class="marketplace-transaction-center__actions">
                  {{#if item.canConfirm}}
                    <button
                      type="button"
                      class="btn btn-primary btn-small"
                      disabled={{eq this.busyTransactionId item.id}}
                      {{on "click" (fn this.confirm item)}}
                    >
                      {{i18n "marketplace.transaction.confirm_button"}}
                    </button>
                  {{/if}}
                  {{#if item.canCancel}}
                    <button
                      type="button"
                      class="btn btn-small"
                      disabled={{eq this.busyTransactionId item.id}}
                      {{on "click" (fn this.cancelTransaction item)}}
                    >
                      {{i18n "marketplace.transaction.cancel_button"}}
                    </button>
                  {{/if}}
                </div>
              {{/if}}

              <PluginOutlet
                @name="marketplace-transaction-after-actions"
                @outletArgs={{lazyHash
                  listing=(hash id=item.listingId title=item.title)
                  transaction=item.transaction
                }}
                @defaultGlimmer={{true}}
              />
            </article>
          {{/each}}
        </div>

        {{#if this.hasMore}}
          <button
            type="button"
            class="btn marketplace-transaction-center__load-more"
            disabled={{this.loading}}
            {{on "click" this.loadMore}}
          >
            {{i18n "marketplace.transaction.load_more"}}
          </button>
        {{/if}}
      {{else}}
        <p class="marketplace-transaction-center__empty">
          {{i18n "marketplace.transactions.empty"}}
        </p>
      {{/if}}
    </div>
  </template>
}
