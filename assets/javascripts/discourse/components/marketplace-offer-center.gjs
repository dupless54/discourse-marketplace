import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import MarketplaceNav from "./marketplace-nav";

const ROLES = ["buyer", "seller"];
const STATUSES = ["all", "pending", "accepted", "rejected", "withdrawn", "expired"];

function formatPrice(cents, currency) {
  return `${(cents / 100).toFixed(2)} ${currency}`;
}

function formatDate(iso) {
  return iso ? new Date(iso).toLocaleString() : "";
}

function amountToCents(value) {
  const normalized = value.trim().replace(",", ".");
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) {
    return null;
  }
  const [whole, fraction = ""] = normalized.split(".");
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  return Number.isSafeInteger(cents) && cents > 0 ? cents : null;
}

export default class MarketplaceOfferCenter extends Component {
  @service currentUser;

  @tracked role = this.args.initialRole || "buyer";
  @tracked status = "all";
  @tracked offers = this.args.initialResult.offers;
  @tracked hasMore = this.args.initialResult.pagination.has_more;
  @tracked page = this.args.initialResult.pagination.page;
  @tracked loading = false;
  @tracked busyOfferId = null;
  @tracked errorMessage = null;
  @tracked counterOfferId = null;
  @tracked counterAmount = "";

  get roleTabs() {
    return ROLES.map((value) => ({
      value,
      label: i18n(`marketplace.offers.tabs.${value}`),
      active: value === this.role,
    }));
  }

  get statusFilters() {
    return STATUSES.map((value) => ({
      value,
      label:
        value === "all"
          ? i18n("marketplace.offers.filters.all")
          : i18n(`marketplace.offer.status.${value}`),
    }));
  }

  get offerViewModels() {
    return this.offers.map((offer) => {
      const pending = offer.status === "pending";
      const isProposer = offer.proposed_by_id === this.currentUser?.id;
      const counterparty =
        this.currentUser?.id === offer.buyer_id ? offer.seller : offer.buyer;

      return {
        offer,
        id: offer.id,
        listingId: offer.listing_id,
        title: offer.listing_title,
        amount: formatPrice(offer.amount_cents, offer.currency),
        askingPrice: formatPrice(offer.asking_price_cents, offer.currency),
        expiresAt: formatDate(offer.expires_at),
        status: offer.status,
        counterpartyUsername: counterparty?.username,
        canRespond: pending && !isProposer,
        canWithdraw: pending && isProposer,
      };
    });
  }

  async fetchOffers(page) {
    this.loading = true;
    this.errorMessage = null;
    try {
      const data = { role: this.role, page };
      if (this.status !== "all") {
        data.status = this.status;
      }
      const result = await ajax("/marketplace/offers/mine", { data });
      this.offers =
        page === 1 ? result.offers : [...this.offers, ...result.offers];
      this.page = result.pagination.page;
      this.hasMore = result.pagination.has_more;
    } catch {
      this.errorMessage = i18n("marketplace.offer.error");
    } finally {
      this.loading = false;
    }
  }

  replaceOffer(updated) {
    this.offers = this.offers.map((offer) =>
      offer.id === updated.id ? { ...offer, ...updated } : offer
    );
  }

  async runAction(offerId, fn) {
    this.busyOfferId = offerId;
    this.errorMessage = null;
    try {
      await fn();
    } catch (error) {
      const type = error.jqXHR?.responseJSON?.error_type;
      this.errorMessage = type
        ? i18n(`marketplace.offer.errors.${type}`)
        : i18n("marketplace.offer.error");
    } finally {
      this.busyOfferId = null;
    }
  }

  @action
  selectTab(role) {
    if (role === this.role) {
      return;
    }
    this.role = role;
    this.counterOfferId = null;
    this.fetchOffers(1);
  }

  @action
  selectStatus(event) {
    this.status = event.target.value;
    this.counterOfferId = null;
    this.fetchOffers(1);
  }

  @action
  loadMore() {
    this.fetchOffers(this.page + 1);
  }

  @action
  beginCounter(item) {
    this.counterOfferId = item.id;
    this.counterAmount = (item.offer.amount_cents / 100).toFixed(2);
  }

  @action
  setCounterAmount(event) {
    this.counterAmount = event.target.value;
  }

  @action
  cancelCounter() {
    this.counterOfferId = null;
    this.counterAmount = "";
  }

  @action
  counter(item) {
    const amountCents = amountToCents(this.counterAmount);
    if (!amountCents) {
      this.errorMessage = i18n("marketplace.offer.invalid_amount");
      return;
    }

    this.runAction(item.id, async () => {
      const result = await ajax(`/marketplace/offers/${item.id}/counter`, {
        type: "POST",
        data: { amount_cents: amountCents },
      });
      this.replaceOffer(result.offer);
      this.cancelCounter();
    });
  }

  @action
  accept(item) {
    this.runAction(item.id, async () => {
      const result = await ajax(`/marketplace/offers/${item.id}/accept`, {
        type: "POST",
      });
      this.replaceOffer(result.offer);
    });
  }

  @action
  reject(item) {
    this.runAction(item.id, async () => {
      const result = await ajax(`/marketplace/offers/${item.id}/reject`, {
        type: "POST",
      });
      this.replaceOffer(result.offer);
    });
  }

  @action
  withdraw(item) {
    this.runAction(item.id, async () => {
      const result = await ajax(`/marketplace/offers/${item.id}/withdraw`, {
        type: "POST",
      });
      this.replaceOffer(result.offer);
    });
  }

  <template>
    <div class="marketplace-offer-center">
      <MarketplaceNav />
      <h1>{{i18n "marketplace.offers.title"}}</h1>

      <div class="marketplace-offer-center__tabs">
        {{#each this.roleTabs as |tab|}}
          <button
            type="button"
            class={{concat
              "btn marketplace-offer-center__tab"
              (if tab.active " marketplace-offer-center__tab--active" "")
            }}
            disabled={{this.loading}}
            {{on "click" (fn this.selectTab tab.value)}}
          >{{tab.label}}</button>
        {{/each}}
      </div>

      <div class="marketplace-offer-center__filters">
        <select aria-label={{i18n "marketplace.offers.status_filter"}} {{on "change" this.selectStatus}}>
          {{#each this.statusFilters as |filter|}}
            <option value={{filter.value}}>{{filter.label}}</option>
          {{/each}}
        </select>
      </div>

      {{#if this.errorMessage}}
        <div class="marketplace-offer-center__error">{{this.errorMessage}}</div>
      {{/if}}

      {{#if this.offerViewModels.length}}
        <div class="marketplace-offer-center__list">
          {{#each this.offerViewModels as |item|}}
            <article class="marketplace-offer-card" data-offer-id={{item.id}}>
              <div class="marketplace-offer-card__main">
                <LinkTo @route="marketplace.listing" @model={{item.listingId}}>
                  <h2>{{item.title}}</h2>
                </LinkTo>
                <p>{{i18n "marketplace.offer.counterparty" username=item.counterpartyUsername}}</p>
                <p class="marketplace-offer-card__amount">{{item.amount}}</p>
                <p>{{i18n "marketplace.offer.asking_price" price=item.askingPrice}}</p>
                {{#if (eq item.status "pending")}}
                  <p>{{i18n "marketplace.offer.expires" date=item.expiresAt}}</p>
                {{/if}}
                <span class="marketplace-offer-card__status">{{i18n
                    (concat "marketplace.offer.status." item.status)
                  }}</span>
              </div>

              {{#if item.canRespond}}
                <div class="marketplace-offer-card__actions">
                  <button
                    type="button"
                    class="btn btn-primary"
                    disabled={{eq this.busyOfferId item.id}}
                    {{on "click" (fn this.accept item)}}
                  >{{i18n "marketplace.offer.accept"}}</button>
                  <button
                    type="button"
                    class="btn"
                    disabled={{eq this.busyOfferId item.id}}
                    {{on "click" (fn this.reject item)}}
                  >{{i18n "marketplace.offer.reject"}}</button>
                  <button
                    type="button"
                    class="btn"
                    disabled={{eq this.busyOfferId item.id}}
                    {{on "click" (fn this.beginCounter item)}}
                  >{{i18n "marketplace.offer.counter"}}</button>
                </div>
              {{else if item.canWithdraw}}
                <button
                  type="button"
                  class="btn"
                  disabled={{eq this.busyOfferId item.id}}
                  {{on "click" (fn this.withdraw item)}}
                >{{i18n "marketplace.offer.withdraw"}}</button>
              {{/if}}

              {{#if (eq this.counterOfferId item.id)}}
                <div class="marketplace-offer-card__counter-form">
                  <label>
                    {{i18n "marketplace.offer.amount_label"}}
                    <input
                      type="text"
                      inputmode="decimal"
                      value={{this.counterAmount}}
                      {{on "input" this.setCounterAmount}}
                    />
                  </label>
                  <span>{{item.offer.currency}}</span>
                  <button
                    type="button"
                    class="btn btn-primary"
                    disabled={{eq this.busyOfferId item.id}}
                    {{on "click" (fn this.counter item)}}
                  >{{i18n "marketplace.offer.send_counter"}}</button>
                  <button type="button" class="btn" {{on "click" this.cancelCounter}}>
                    {{i18n "marketplace.offer.cancel"}}
                  </button>
                </div>
              {{/if}}
            </article>
          {{/each}}
        </div>
      {{else}}
        <p class="marketplace-offer-center__empty">{{i18n "marketplace.offers.empty"}}</p>
      {{/if}}

      {{#if this.hasMore}}
        <button
          type="button"
          class="btn marketplace-offer-center__load-more"
          disabled={{this.loading}}
          {{on "click" this.loadMore}}
        >{{i18n "marketplace.offers.load_more"}}</button>
      {{/if}}
    </div>
  </template>
}
