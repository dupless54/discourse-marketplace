import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Textarea } from "@ember/component";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { getUploadMarkdown } from "discourse/lib/uploads";
import UppyUpload from "discourse/lib/uppy/uppy-upload";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
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

  uppyUpload = new UppyUpload(getOwner(this), {
    id: "marketplace-listing-upload",
    type: "composer",
    uploadDone: this.uploadDone,
  });

  get currencies() {
    return this.siteSettings.marketplace_allowed_currencies.split("|");
  }

  get isEdit() {
    return !!this.args.listing;
  }

  get uploading() {
    return this.uppyUpload.uploading || this.uppyUpload.processing;
  }

  get uploadButtonLabel() {
    return this.uploading
      ? "marketplace.form.upload_uploading"
      : "marketplace.form.upload_button";
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
  pickUpload() {
    this.uppyUpload.openPicker();
  }

  @action
  uploadDone(upload) {
    const markdown = getUploadMarkdown(upload);
    this.raw = this.raw ? `${this.raw}\n${markdown}` : markdown;
  }

  @action
  updateCategoryId(event) {
    this.categoryId = event.target.value ? Number(event.target.value) : "";
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
      <h1 class="marketplace-listing-form__heading">
        {{#if this.isEdit}}
          {{i18n "marketplace.form.edit_title"}}
        {{else}}
          {{i18n "marketplace.form.new_title"}}
        {{/if}}
      </h1>

      {{#if this.errorMessage}}
        <div class="marketplace-listing-form__error">{{this.errorMessage}}</div>
      {{/if}}

      <div class="marketplace-listing-form__field">
        <label>{{i18n "marketplace.form.title_label"}}</label>
        <input
          type="text"
          value={{this.title}}
          {{on "input" this.updateTitle}}
        />
      </div>

      <div class="marketplace-listing-form__field">
        <label>{{i18n "marketplace.form.description_label"}}</label>
        <Textarea
          @value={{this.raw}}
          rows="8"
          class="marketplace-listing-form__description"
          {{on "input" this.updateRaw}}
        />
      </div>

      <div class="marketplace-listing-form__field marketplace-listing-form__upload">
        <input
          {{didInsert this.uppyUpload.setup}}
          type="file"
          class="marketplace-listing-form__upload-input hidden-upload-field"
          disabled={{this.uploading}}
        />
        <DButton
          class="btn-default marketplace-listing-form__upload-button"
          @label={{this.uploadButtonLabel}}
          @icon="upload"
          @action={{this.pickUpload}}
          @disabled={{this.uploading}}
        />
        {{#if this.uploading}}
          <span class="marketplace-listing-form__upload-progress">
            {{this.uppyUpload.uploadProgress}}%
          </span>
        {{/if}}
      </div>

      <div class="marketplace-listing-form__field">
        <label>{{i18n "marketplace.form.category_label"}}</label>
        <select {{on "change" this.updateCategoryId}}>
          <option value="">{{i18n "marketplace.form.category_placeholder"}}</option>
          {{#each @categories as |category|}}
            <option
              value={{category.id}}
              selected={{eq category.id this.categoryId}}
            >{{category.name}}</option>
          {{/each}}
        </select>
      </div>

      <div class="marketplace-listing-form__row">
        <div class="marketplace-listing-form__field marketplace-listing-form__price-field">
          <label>{{i18n "marketplace.form.price_label"}}</label>
          <input
            type="number"
            min="0"
            step="0.01"
            value={{this.price}}
            {{on "input" this.updatePrice}}
          />
        </div>

        <div class="marketplace-listing-form__field marketplace-listing-form__currency-field">
          <label>{{i18n "marketplace.form.currency_label"}}</label>
          <select {{on "change" this.updateCurrency}}>
            {{#each this.currencies as |currencyCode|}}
              <option
                value={{currencyCode}}
                selected={{eq currencyCode this.currency}}
              >{{currencyCode}}</option>
            {{/each}}
          </select>
        </div>
      </div>

      <div class="marketplace-listing-form__actions">
        <button type="submit" class="btn btn-primary" disabled={{this.saving}}>
          {{#if this.isEdit}}
            {{i18n "marketplace.form.submit_save"}}
          {{else}}
            {{i18n "marketplace.form.submit_create"}}
          {{/if}}
        </button>
      </div>
    </form>
  </template>
}
