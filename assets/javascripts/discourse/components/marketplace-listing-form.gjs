import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default class MarketplaceListingForm extends Component {
  @service router;
  @service siteSettings;

  @tracked title = this.args.listing?.title ?? "";
  @tracked raw = this.args.listing?.raw ?? "";
  @tracked categoryId = this.args.listing?.category_id ?? "";
  @tracked price = this.args.listing?.price_cents
    ? (this.args.listing.price_cents / 100).toFixed(2)
    : "";
  @tracked currency =
    this.args.listing?.currency ??
    this.siteSettings.marketplace_allowed_currencies.split("|")[0];
  @tracked saving = false;
  @tracked errorMessage = null;

  get currencies() {
    return this.siteSettings.marketplace_allowed_currencies.split("|");
  }

  get isEdit() {
    return !!this.args.listing;
  }

  @action
  updateTitle(event) {
    this.title = event.target.value;
  }

  @action
  updateRaw(event) {
    this.raw = event.target.value;
  }

  @action
  updateCategoryId(event) {
    this.categoryId = event.target.value;
  }

  @action
  updatePrice(event) {
    this.price = event.target.value;
  }

  @action
  updateCurrency(event) {
    this.currency = event.target.value;
  }

  @action
  async submit(event) {
    event.preventDefault();
    this.saving = true;
    this.errorMessage = null;

    const data = {
      title: this.title,
      raw: this.raw,
      category_id: this.categoryId,
      price_cents: Math.round(parseFloat(this.price || "0") * 100),
      currency: this.currency,
    };

    try {
      const result = this.isEdit
        ? await ajax(`/marketplace/listings/${this.args.listing.id}`, {
            type: "PUT",
            data,
          })
        : await ajax("/marketplace/listings", { type: "POST", data });

      this.router.transitionTo("marketplace.listing", result.listing.id);
    } catch (error) {
      this.errorMessage =
        error.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("marketplace.form.error");
    } finally {
      this.saving = false;
    }
  }

  <template>
    <form class="marketplace-listing-form" {{on "submit" this.submit}}>
      <h1>
        {{#if this.isEdit}}
          {{i18n "marketplace.form.edit_title"}}
        {{else}}
          {{i18n "marketplace.form.new_title"}}
        {{/if}}
      </h1>

      {{#if this.errorMessage}}
        <div class="marketplace-listing-form__error">{{this.errorMessage}}</div>
      {{/if}}

      <label>
        {{i18n "marketplace.form.title_label"}}
        <input
          type="text"
          value={{this.title}}
          {{on "input" this.updateTitle}}
        />
      </label>

      <label>
        {{i18n "marketplace.form.description_label"}}
        <textarea rows="8" {{on "input" this.updateRaw}}>{{this.raw}}</textarea>
      </label>

      <label>
        {{i18n "marketplace.form.category_label"}}
        <select {{on "change" this.updateCategoryId}}>
          <option value="">{{i18n "marketplace.form.category_placeholder"}}</option>
          {{#each @categories as |category|}}
            <option
              value={{category.id}}
              selected={{eq category.id this.categoryId}}
            >{{category.name}}</option>
          {{/each}}
        </select>
      </label>

      <label>
        {{i18n "marketplace.form.price_label"}}
        <input
          type="number"
          min="0"
          step="0.01"
          value={{this.price}}
          {{on "input" this.updatePrice}}
        />
      </label>

      <label>
        {{i18n "marketplace.form.currency_label"}}
        <select {{on "change" this.updateCurrency}}>
          {{#each this.currencies as |currencyCode|}}
            <option
              value={{currencyCode}}
              selected={{eq currencyCode this.currency}}
            >{{currencyCode}}</option>
          {{/each}}
        </select>
      </label>

      <button type="submit" class="btn btn-primary" disabled={{this.saving}}>
        {{#if this.isEdit}}
          {{i18n "marketplace.form.submit_save"}}
        {{else}}
          {{i18n "marketplace.form.submit_create"}}
        {{/if}}
      </button>
    </form>
  </template>
}
