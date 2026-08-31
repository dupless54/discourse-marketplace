import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

function formatPrice(cents, currency) {
  return `${(cents / 100).toFixed(2)} ${currency}`;
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

export default class MarketplaceOfferPanel extends Component {
  @service currentUser;
  @service router;

  @tracked offers = [];
  @tracked loading = false;
  @tracked busyOfferId = null;
  @tracked creating = false;
  @tracked offerAmount = "";
  @tracked counterOfferId = null;
  @tracked counterAmount = "";
  @tracked errorMessage = null;

  get isSeller() {
    return this.currentUser?.id === this.args.listing.seller.id;
  }

  get pendingOffers() {
    return this.offers.filter((offer) => offer.status === "pending");
  }

  get canCreateOffer() {
    return (
      this.currentUser &&
      !this.isSeller &&
      this.args.listing.purchasable &&
      !this.args.hasPendingTransaction &&
      this.pendingOffers.length === 0
    );
  }

  get offerItems() {
    return this.offers.map((offer) => {
      const pending = offer.status === "pending";
      const isProposer = offer.proposed_by_id === this.currentUser?.id;
      return {
        offer,
        id: offer.id,
        buyerUsername: offer.buyer?.username,
        amount: formatPrice(offer.amount_cents, offer.currency),
        status: offer.status,
        canRespond: pending && !isProposer,
        canWithdraw: pending && isProposer,
      };
    });
  }

  @action
  async loadOffers() {
    if (!this.currentUser || this.loading) {
      return;
    }

    this.loading = true;
    this.errorMessage = null;
    try {
      const result = await ajax(
        `/marketplace/listings/${this.args.listing.id}/offers`,
        { data: { page: 1, per_page: 50 } }
      );
      this.offers = result.offers;
    } catch {
      this.errorMessage = i18n("marketplace.offer.error");
    } finally {
      this.loading = false;
    }
  }

  setError(error) {
    const type = error.jqXHR?.responseJSON?.error_type;
    this.errorMessage = type
      ? i18n(`marketplace.offer.errors.${type}`)
      : i18n("marketplace.offer.error");
  }

  replaceOffer(updated) {
    const exists = this.offers.some((offer) => offer.id === updated.id);
    this.offers = exists
      ? this.offers.map((offer) =>
          offer.id === updated.id ? { ...offer, ...updated } : offer
        )
      : [updated, ...this.offers];
  }

  async runOfferAction(offerId, fn) {
    if (this.busyOfferId) {
      return;
    }

    this.busyOfferId = offerId;
    this.errorMessage = null;
    try {
      await fn();
    } catch (error) {
      this.setError(error);
    } finally {
      this.busyOfferId = null;
    }
  }

  @action
  setOfferAmount(event) {
    this.offerAmount = event.target.value;
  }

  @action
  createOffer() {
    if (this.creating) {
      return;
    }

    const amountCents = amountToCents(this.offerAmount);
    if (!amountCents) {
      this.errorMessage = i18n("marketplace.offer.invalid_amount");
      return;
    }

    this.creating = true;
    this.errorMessage = null;
    ajax("/marketplace/offers", {
      type: "POST",
      data: { listing_id: this.args.listing.id, amount_cents: amountCents },
    })
      .then((result) => {
        this.replaceOffer(result.offer);
        this.offerAmount = "";
      })
      .catch((error) => this.setError(error))
      .finally(() => (this.creating = false));
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

    this.runOfferAction(item.id, async () => {
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
    this.runOfferAction(item.id, async () => {
      const result = await ajax(`/marketplace/offers/${item.id}/accept`, {
        type: "POST",
      });
      this.replaceOffer(result.offer);
      this.router.transitionTo("marketplace.listing", this.args.listing.id, {
        queryParams: { transaction_id: result.transaction.id },
      });
    });
  }

  @action
  reject(item) {
    this.runOfferAction(item.id, async () => {
      const result = await ajax(`/marketplace/offers/${item.id}/reject`, {
        type: "POST",
      });
      this.replaceOffer(result.offer);
    });
  }

  @action
  withdraw(item) {
    this.runOfferAction(item.id, async () => {
      const result = await ajax(`/marketplace/offers/${item.id}/withdraw`, {
        type: "POST",
      });
      this.replaceOffer(result.offer);
    });
  }

  <template>
    {{#if this.currentUser}}
      <section class="marketplace-offer-panel" {{didInsert this.loadOffers}}>
        <h2>{{i18n "marketplace.offer.panel_title"}}</h2>

        {{#if this.errorMessage}}
          <div class="marketplace-offer-panel__error" role="alert">
            {{this.errorMessage}}
          </div>
        {{/if}}

        {{#if this.canCreateOffer}}
          <div class="marketplace-offer-panel__new">
            <label>
              {{i18n "marketplace.offer.amount_label"}}
              <div class="marketplace-offer-panel__amount-input">
                <input
                  type="text"
                  inputmode="decimal"
                  value={{this.offerAmount}}
                  placeholder={{i18n "marketplace.offer.amount_placeholder"}}
                  {{on "input" this.setOfferAmount}}
                />
                <span>{{@listing.currency}}</span>
              </div>
            </label>
            <DButton
              class="btn-primary"
              @label="marketplace.offer.submit"
              @action={{this.createOffer}}
              @disabled={{this.creating}}
              @isLoading={{this.creating}}
            />
          </div>
        {{/if}}

        {{#if this.offerItems.length}}
          <div class="marketplace-offer-panel__list">
            {{#each this.offerItems as |item|}}
              <article
                class="marketplace-offer-panel__item"
                data-offer-id={{item.id}}
              >
                {{#if this.isSeller}}
                  <strong>{{i18n
                      "marketplace.offer.from_buyer"
                      username=item.buyerUsername
                    }}</strong>
                {{/if}}
                <span
                  class="marketplace-offer-panel__price"
                >{{item.amount}}</span>
                <span class="marketplace-offer-panel__status">{{i18n
                    (concat "marketplace.offer.status." item.status)
                  }}</span>

                {{#if item.canRespond}}
                  <div class="marketplace-offer-panel__actions">
                    <DButton
                      class="btn-primary"
                      @label="marketplace.offer.accept"
                      @action={{fn this.accept item}}
                      @disabled={{eq this.busyOfferId item.id}}
                      @isLoading={{eq this.busyOfferId item.id}}
                    />
                    <DButton
                      @label="marketplace.offer.reject"
                      @action={{fn this.reject item}}
                      @disabled={{eq this.busyOfferId item.id}}
                    />
                    <DButton
                      @label="marketplace.offer.counter"
                      @action={{fn this.beginCounter item}}
                      @disabled={{eq this.busyOfferId item.id}}
                    />
                  </div>
                {{else if item.canWithdraw}}
                  <DButton
                    @label="marketplace.offer.withdraw"
                    @action={{fn this.withdraw item}}
                    @disabled={{eq this.busyOfferId item.id}}
                    @isLoading={{eq this.busyOfferId item.id}}
                  />
                {{/if}}

                {{#if (eq this.counterOfferId item.id)}}
                  <div class="marketplace-offer-panel__counter">
                    <input
                      type="text"
                      inputmode="decimal"
                      value={{this.counterAmount}}
                      aria-label={{i18n "marketplace.offer.amount_label"}}
                      {{on "input" this.setCounterAmount}}
                    />
                    <span>{{item.offer.currency}}</span>
                    <DButton
                      class="btn-primary"
                      @label="marketplace.offer.send_counter"
                      @action={{fn this.counter item}}
                      @disabled={{eq this.busyOfferId item.id}}
                      @isLoading={{eq this.busyOfferId item.id}}
                    />
                    <DButton
                      @label="marketplace.offer.cancel"
                      @action={{this.cancelCounter}}
                      @disabled={{eq this.busyOfferId item.id}}
                    />
                  </div>
                {{/if}}
              </article>
            {{/each}}
          </div>
        {{else if this.loading}}
          <p role="status">{{i18n "marketplace.offer.loading"}}</p>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
