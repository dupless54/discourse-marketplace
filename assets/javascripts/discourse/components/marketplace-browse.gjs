import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import MarketplaceListingCard from "./marketplace-listing-card";
import MarketplaceNav from "./marketplace-nav";

export default class MarketplaceBrowse extends Component {
  @tracked listings = this.args.initialListingsResult.listings;
  @tracked hasMore = this.args.initialListingsResult.pagination.has_more;
  @tracked page = this.args.initialListingsResult.pagination.page;
  @tracked loading = false;
  @tracked categoryId = "";
  @tracked query = "";
  @tracked sort = "newest";
  @tracked fieldFilters = {};

  get sorts() {
    return [
      { value: "newest", label: i18n("marketplace.browse.sort_newest") },
      { value: "price_asc", label: i18n("marketplace.browse.sort_price_asc") },
      { value: "price_desc", label: i18n("marketplace.browse.sort_price_desc") },
    ];
  }

  get selectedCategory() {
    return (this.args.categories ?? []).find(
      (category) => category.id === Number(this.categoryId)
    );
  }

  get featuredCategories() {
    return (this.args.categories ?? []).slice(0, 5);
  }

  get structuredFiltersForForm() {
    return (this.selectedCategory?.field_definitions ?? []).map((field) => {
      const current = this.fieldFilters[field.key];
      if (field.type === "integer") {
        return {
          ...field,
          minValue: current?.min ?? "",
          maxValue: current?.max ?? "",
        };
      }
      return { ...field, value: current ?? "" };
    });
  }

  get activeFilterChips() {
    const chips = [];
    const trimmedQuery = this.query.trim();

    if (trimmedQuery) {
      chips.push({ type: "query", key: "query", label: trimmedQuery });
    }

    if (this.selectedCategory) {
      chips.push({
        type: "category",
        key: "category",
        label: this.selectedCategory.name,
      });
    }

    for (const field of this.structuredFiltersForForm) {
      if (field.type === "integer") {
        const parts = [];
        if (field.minValue !== "") {
          parts.push(`${i18n("marketplace.browse.integer_min")} ${field.minValue}`);
        }
        if (field.maxValue !== "") {
          parts.push(`${i18n("marketplace.browse.integer_max")} ${field.maxValue}`);
        }
        if (parts.length) {
          chips.push({
            type: "field",
            key: field.key,
            label: `${field.label}: ${parts.join(" · ")}`,
          });
        }
        continue;
      }

      if (field.value === "") {
        continue;
      }

      let displayValue = field.value;
      if (field.type === "select") {
        displayValue =
          field.choices.find((choice) => choice.value === field.value)?.label ??
          field.value;
      } else if (field.type === "boolean") {
        displayValue = i18n(
          field.value === "true"
            ? "marketplace.listing.boolean_yes"
            : "marketplace.listing.boolean_no"
        );
      }

      chips.push({
        type: "field",
        key: field.key,
        label: `${field.label}: ${displayValue}`,
      });
    }

    return chips;
  }

  get hasActiveFilters() {
    return this.activeFilterChips.length > 0 || this.sort !== "newest";
  }

  addStructuredFilters(params) {
    for (const field of this.structuredFiltersForForm) {
      if (field.type === "integer") {
        if (field.minValue !== "") {
          params[`field_filters[${field.key}][min]`] = field.minValue;
        }
        if (field.maxValue !== "") {
          params[`field_filters[${field.key}][max]`] = field.maxValue;
        }
      } else if (field.value !== "") {
        params[`field_filters[${field.key}]`] = field.value;
      }
    }
  }

  async fetchListings(page) {
    if (this.loading) {
      return;
    }

    this.loading = true;
    try {
      const params = { page, sort: this.sort };
      if (this.categoryId) {
        params.category_id = this.categoryId;
      }
      if (this.query.trim()) {
        params.q = this.query.trim();
      }
      this.addStructuredFilters(params);

      const result = await ajax("/marketplace/listings", { data: params });
      this.listings =
        page === 1 ? result.listings : [...this.listings, ...result.listings];
      this.hasMore = result.pagination.has_more;
      this.page = result.pagination.page;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action updateQuery(event) {
    this.query = event.target.value;
  }

  @action updateCategory(event) {
    if (this.loading) {
      return;
    }
    this.categoryId = event.target.value ? Number(event.target.value) : "";
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action selectCategory(category) {
    if (this.loading) {
      return;
    }
    this.categoryId = Number(this.categoryId) === category.id ? "" : category.id;
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action showAllCategories() {
    if (this.loading) {
      return;
    }
    this.categoryId = "";
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action updateSort(event) {
    if (this.loading) {
      return;
    }
    this.sort = event.target.value;
    this.fetchListings(1);
  }

  @action updateStructuredFilter(field, event) {
    this.fieldFilters = { ...this.fieldFilters, [field.key]: event.target.value };
  }

  @action updateIntegerStructuredFilter(field, bound, event) {
    const current = this.fieldFilters[field.key] ?? {};
    this.fieldFilters = {
      ...this.fieldFilters,
      [field.key]: { ...current, [bound]: event.target.value },
    };
  }

  @action clearStructuredFilters() {
    if (this.loading) {
      return;
    }
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action clearFilterChip(chip) {
    if (this.loading) {
      return;
    }
    if (chip.type === "query") {
      this.query = "";
    } else if (chip.type === "category") {
      this.categoryId = "";
      this.fieldFilters = {};
    } else if (chip.type === "field") {
      const nextFilters = { ...this.fieldFilters };
      delete nextFilters[chip.key];
      this.fieldFilters = nextFilters;
    }
    this.fetchListings(1);
  }

  @action clearAllFilters() {
    if (this.loading) {
      return;
    }
    this.query = "";
    this.categoryId = "";
    this.sort = "newest";
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action search(event) {
    event.preventDefault();
    this.fetchListings(1);
  }

  @action loadMore() {
    if (this.hasMore) {
      this.fetchListings(this.page + 1);
    }
  }

  <template>
    <main class="marketplace-browse marketplace-browse--showcase marketplace-browse--compact-feed marketplace-page">
      <header class="marketplace-browse__header">
        <div class="marketplace-browse__title-wrap">
          <span class="marketplace-browse__title-icon">{{dIcon "tag"}}</span>
          <h1>{{i18n "marketplace.title"}}</h1>
        </div>
      </header>

      <MarketplaceNav />

      <form class="marketplace-browse__filters" {{on "submit" this.search}}>
        <div class="marketplace-browse__primary-filters">
          <label class="marketplace-browse__search-shell">
            <span class="marketplace-browse__search-icon">{{dIcon "magnifying-glass"}}</span>
            <input
              type="text"
              class="marketplace-browse__search"
              aria-label={{i18n "marketplace.browse.search_placeholder"}}
              placeholder={{i18n "marketplace.browse.search_placeholder"}}
              value={{this.query}}
              disabled={{this.loading}}
              {{on "input" this.updateQuery}}
            />
          </label>

          <select
            class="marketplace-browse__category"
            aria-label={{i18n "marketplace.browse.category_all"}}
            disabled={{this.loading}}
            {{on "change" this.updateCategory}}
          >
            <option value="">{{i18n "marketplace.browse.category_all"}}</option>
            {{#each @categories as |category|}}
              <option value={{category.id}} selected={{eq category.id this.categoryId}}>
                {{category.name}}
              </option>
            {{/each}}
          </select>

          <select
            class="marketplace-browse__sort"
            aria-label={{i18n "marketplace.browse.sort_label"}}
            disabled={{this.loading}}
            {{on "change" this.updateSort}}
          >
            {{#each this.sorts as |sortOption|}}
              <option value={{sortOption.value}} selected={{eq sortOption.value this.sort}}>
                {{sortOption.label}}
              </option>
            {{/each}}
          </select>

          <DButton
            class="btn-primary marketplace-browse__search-button"
            @type="submit"
            @label="marketplace.browse.search_button"
            @icon="magnifying-glass"
            @disabled={{this.loading}}
            @isLoading={{this.loading}}
          />
        </div>

        <div class="marketplace-browse__filter-chips">
          <button
            type="button"
            class={{if
              this.hasActiveFilters
              "marketplace-browse__filter-chip"
              "marketplace-browse__filter-chip marketplace-browse__filter-chip--active"
            }}
            aria-pressed={{not this.hasActiveFilters}}
            disabled={{this.loading}}
            {{on "click" this.clearAllFilters}}
          >
            {{i18n "marketplace.browse.all_filter"}}
          </button>

          {{#each this.activeFilterChips as |chip|}}
            <button
              type="button"
              class="marketplace-browse__filter-chip marketplace-browse__filter-chip--selected"
              disabled={{this.loading}}
              {{on "click" (fn this.clearFilterChip chip)}}
            >
              <span>{{chip.label}}</span>
              <span aria-hidden="true">×</span>
            </button>
          {{/each}}

          {{#if this.hasActiveFilters}}
            <DButton
              class="btn-flat marketplace-browse__clear-all-filters"
              @label="marketplace.browse.clear_filters"
              @action={{this.clearAllFilters}}
              @disabled={{this.loading}}
            />
          {{/if}}
        </div>

        {{#if this.structuredFiltersForForm.length}}
          <section class="marketplace-browse__dynamic-filters">
            <div class="marketplace-browse__dynamic-filters-header">
              <h2>{{i18n "marketplace.browse.dynamic_filters"}}</h2>
              <DButton
                class="btn-flat marketplace-browse__clear-filters"
                @label="marketplace.browse.clear_filters"
                @action={{this.clearStructuredFilters}}
                @disabled={{this.loading}}
              />
            </div>

            <div class="marketplace-browse__dynamic-filter-grid">
              {{#each this.structuredFiltersForForm as |field|}}
                <div class="marketplace-browse__dynamic-filter" data-filter-key={{field.key}}>
                  <span class="marketplace-browse__dynamic-filter-label">{{field.label}}</span>

                  {{#if (eq field.type "integer")}}
                    <div class="marketplace-browse__integer-range">
                      <label>
                        <span>{{i18n "marketplace.browse.integer_min"}}</span>
                        <input
                          type="number"
                          step="1"
                          value={{field.minValue}}
                          disabled={{this.loading}}
                          {{on "input" (fn this.updateIntegerStructuredFilter field "min")}}
                        />
                      </label>
                      <label>
                        <span>{{i18n "marketplace.browse.integer_max"}}</span>
                        <input
                          type="number"
                          step="1"
                          value={{field.maxValue}}
                          disabled={{this.loading}}
                          {{on "input" (fn this.updateIntegerStructuredFilter field "max")}}
                        />
                      </label>
                    </div>
                  {{else if (eq field.type "select")}}
                    <select
                      aria-label={{field.label}}
                      disabled={{this.loading}}
                      {{on "change" (fn this.updateStructuredFilter field)}}
                    >
                      <option value="">{{i18n "marketplace.browse.filter_any"}}</option>
                      {{#each field.choices as |choice|}}
                        <option value={{choice.value}} selected={{eq choice.value field.value}}>
                          {{choice.label}}
                        </option>
                      {{/each}}
                    </select>
                  {{else if (eq field.type "boolean")}}
                    <select
                      aria-label={{field.label}}
                      disabled={{this.loading}}
                      {{on "change" (fn this.updateStructuredFilter field)}}
                    >
                      <option value="">{{i18n "marketplace.browse.filter_any"}}</option>
                      <option value="true" selected={{eq field.value "true"}}>
                        {{i18n "marketplace.listing.boolean_yes"}}
                      </option>
                      <option value="false" selected={{eq field.value "false"}}>
                        {{i18n "marketplace.listing.boolean_no"}}
                      </option>
                    </select>
                  {{else}}
                    <input
                      type="text"
                      aria-label={{field.label}}
                      value={{field.value}}
                      disabled={{this.loading}}
                      placeholder={{i18n "marketplace.browse.text_filter_placeholder"}}
                      {{on "input" (fn this.updateStructuredFilter field)}}
                    />
                  {{/if}}
                </div>
              {{/each}}
            </div>
          </section>
        {{/if}}
      </form>

      {{#if this.featuredCategories.length}}
        <section class="marketplace-browse__category-showcase">
          <div class="marketplace-browse__section-heading">
            <h2>{{i18n "marketplace.browse.popular_categories"}}</h2>
            <DButton
              class="btn-flat marketplace-browse__section-link"
              @label="marketplace.browse.view_all_categories"
              @action={{this.showAllCategories}}
              @disabled={{this.loading}}
            />
          </div>

          <div class="marketplace-browse__category-strip">
            {{#each this.featuredCategories as |category|}}
              <button
                type="button"
                class={{if
                  (eq category.id this.categoryId)
                  "marketplace-browse__category-card marketplace-browse__category-card--active"
                  "marketplace-browse__category-card"
                }}
                data-category-id={{category.id}}
                aria-pressed={{eq category.id this.categoryId}}
                disabled={{this.loading}}
                {{on "click" (fn this.selectCategory category)}}
              >
                <span class="marketplace-browse__category-card-icon">{{dIcon "tag"}}</span>
                <span class="marketplace-browse__category-card-copy">
                  <strong>{{category.name}}</strong>
                  <small>{{i18n "marketplace.browse.category_browse_hint"}}</small>
                </span>
              </button>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#if this.listings.length}}
        <section class="marketplace-browse__latest marketplace-browse__results">
          <div class="marketplace-browse__section-heading">
            <h2>{{i18n "marketplace.browse.latest_listings"}}</h2>
          </div>
          <div class="marketplace-browse__listing-list">
            {{#each this.listings as |listing|}}
              <MarketplaceListingCard @listing={{listing}} />
            {{/each}}
          </div>
        </section>

        {{#if this.hasMore}}
          <div class="marketplace-page__load-more">
            <DButton
              class="marketplace-browse__load-more"
              @label="marketplace.browse.load_more"
              @action={{this.loadMore}}
              @disabled={{this.loading}}
              @isLoading={{this.loading}}
            />
          </div>
        {{/if}}
      {{else}}
        <div class="marketplace-page__empty" role="status">
          <p class="marketplace-browse__empty">{{i18n "marketplace.browse.empty"}}</p>
        </div>
      {{/if}}
    </main>
  </template>
}
