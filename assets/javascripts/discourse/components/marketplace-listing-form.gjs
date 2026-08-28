import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Textarea } from "@ember/component";
import { fn } from "@ember/helper";
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
import MarketplaceNav from "./marketplace-nav";

// Converts an ISO8601 string (as returned by the API) into the value a
// <input type="datetime-local"> expects (local time, no seconds/zone), and
// back again on submit. A blank/absent value round-trips to "" both ways,
// which is exactly "no expiration".
function isoToDatetimeLocal(iso) {
  if (!iso) {
    return "";
  }
  const date = new Date(iso);
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(
    date.getDate()
  )}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function datetimeLocalToIso(value) {
  if (!value) {
    return null;
  }
  const date = new Date(value);
  return isNaN(date) ? null : date.toISOString();
}

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
  @tracked inventoryMode = this.args.listing?.inventory_mode ?? "single";
  @tracked stockQuantity = this.args.listing?.stock_quantity ?? "";
  @tracked expiresAt = isoToDatetimeLocal(this.args.listing?.expires_at);
  initialCategoryId = this.args.listing?.category_id ?? "";
  initialCustomFields = Object.fromEntries(
    (this.args.listing?.custom_fields ?? []).map((field) => [
      field.key,
      field.type === "boolean" ? field.value === "true" : field.value,
    ])
  );
  @tracked customFields = { ...this.initialCustomFields };
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

  get isFinite() {
    return this.inventoryMode === "finite";
  }

  get uploading() {
    return this.uppyUpload.uploading || this.uppyUpload.processing;
  }

  get selectedCategory() {
    return this.args.categories.find(
      (category) => category.id === Number(this.categoryId)
    );
  }

  get customFieldsForForm() {
    return (this.selectedCategory?.field_definitions ?? []).map((field) => ({
      ...field,
      value:
        this.customFields[field.key] ?? (field.type === "boolean" ? false : ""),
    }));
  }

  get customFieldPayload() {
    return Object.fromEntries(
      this.customFieldsForForm.map((field) => [field.key, field.value])
    );
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
    this.customFields =
      this.categoryId === this.initialCategoryId
        ? { ...this.initialCustomFields }
        : {};
  }

  @action
  updateCustomField(field, event) {
    const value =
      field.type === "boolean" ? event.target.checked : event.target.value;
    this.customFields = { ...this.customFields, [field.key]: value };
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
  updateInventoryMode(event) {
    this.inventoryMode = event.target.value;
  }

  @action
  updateStockQuantity(event) {
    this.stockQuantity = event.target.value;
  }

  @action
  updateExpiresAt(event) {
    this.expiresAt = event.target.value;
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
      inventory_mode: this.inventoryMode,
      stock_quantity: this.isFinite ? this.stockQuantity : null,
      expires_at: datetimeLocalToIso(this.expiresAt),
      custom_fields: this.customFieldPayload,
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
    <MarketplaceNav />

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
        <select
          class="marketplace-listing-form__category"
          {{on "change" this.updateCategoryId}}
        >
          <option value="">{{i18n "marketplace.form.category_placeholder"}}</option>
          {{#each @categories as |category|}}
            <option
              value={{category.id}}
              selected={{eq category.id this.categoryId}}
            >{{category.name}}</option>
          {{/each}}
        </select>
      </div>

      {{#if this.customFieldsForForm.length}}
        <section class="marketplace-listing-form__structured-fields">
          <h2>{{i18n "marketplace.form.structured_fields_heading"}}</h2>
          <div class="marketplace-listing-form__structured-grid">
            {{#each this.customFieldsForForm as |field|}}
              <div
                class="marketplace-listing-form__field marketplace-listing-form__custom-field"
                data-field-key={{field.key}}
              >
                {{#if (eq field.type "boolean")}}
                  <label class="marketplace-listing-form__boolean-label">
                    <input
                      type="checkbox"
                      checked={{field.value}}
                      {{on "change" (fn this.updateCustomField field)}}
                    />
                    <span>
                      {{field.label}}
                      {{#if field.required}}<span
                          class="marketplace-listing-form__required"
                          aria-hidden="true"
                        >*</span>{{/if}}
                    </span>
                  </label>
                {{else}}
                  <label>
                    {{field.label}}
                    {{#if field.required}}<span
                        class="marketplace-listing-form__required"
                        aria-hidden="true"
                      >*</span>{{/if}}
                  </label>

                  {{#if (eq field.type "textarea")}}
                    <Textarea
                      @value={{field.value}}
                      rows="4"
                      maxlength="5000"
                      placeholder={{field.placeholder}}
                      required={{field.required}}
                      {{on "input" (fn this.updateCustomField field)}}
                    />
                  {{else if (eq field.type "select")}}
                    <select
                      required={{field.required}}
                      {{on "change" (fn this.updateCustomField field)}}
                    >
                      <option value="">{{i18n
                          "marketplace.form.select_placeholder"
                        }}</option>
                      {{#each field.choices as |choice|}}
                        <option
                          value={{choice.value}}
                          selected={{eq choice.value field.value}}
                        >{{choice.label}}</option>
                      {{/each}}
                    </select>
                  {{else}}
                    <input
                      type={{if (eq field.type "integer") "number" "text"}}
                      step={{if (eq field.type "integer") "1"}}
                      maxlength={{if (eq field.type "text") "255"}}
                      value={{field.value}}
                      placeholder={{field.placeholder}}
                      required={{field.required}}
                      {{on "input" (fn this.updateCustomField field)}}
                    />
                  {{/if}}
                {{/if}}

                {{#if field.help_text}}
                  <span class="marketplace-listing-form__hint">{{field.help_text}}</span>
                {{/if}}
              </div>
            {{/each}}
          </div>
        </section>
      {{/if}}

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

      <div class="marketplace-listing-form__field">
        <label>{{i18n "marketplace.form.inventory_mode_label"}}</label>
        <select
          class="marketplace-listing-form__inventory-mode"
          {{on "change" this.updateInventoryMode}}
        >
          <option value="single" selected={{eq this.inventoryMode "single"}}>
            {{i18n "marketplace.form.inventory_mode_single"}}
          </option>
          <option value="finite" selected={{eq this.inventoryMode "finite"}}>
            {{i18n "marketplace.form.inventory_mode_finite"}}
          </option>
          <option
            value="unlimited"
            selected={{eq this.inventoryMode "unlimited"}}
          >
            {{i18n "marketplace.form.inventory_mode_unlimited"}}
          </option>
        </select>
      </div>

      {{#if this.isFinite}}
        <div class="marketplace-listing-form__field marketplace-listing-form__stock-field">
          <label>{{i18n "marketplace.form.stock_quantity_label"}}</label>
          <input
            type="number"
            min="1"
            step="1"
            value={{this.stockQuantity}}
            {{on "input" this.updateStockQuantity}}
          />
        </div>
      {{/if}}

      <div class="marketplace-listing-form__field marketplace-listing-form__expires-field">
        <label>{{i18n "marketplace.form.expires_at_label"}}</label>
        <input
          type="datetime-local"
          value={{this.expiresAt}}
          {{on "input" this.updateExpiresAt}}
        />
        <span class="marketplace-listing-form__hint">
          {{i18n "marketplace.form.expires_at_hint"}}
        </span>
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
