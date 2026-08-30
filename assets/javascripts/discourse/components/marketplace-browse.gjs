import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
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
      {
        value: "price_desc",
        label: i18n("marketplace.browse.sort_price_desc"),
      },
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

  get featuredListings() {
    return this.listings.slice(0, 4);
  }

  get latestListings() {
    return this.listings.slice(4);
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
      chips.push({
        type: "query",
        key: "query",
        label: trimmedQuery,
      });
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
          parts.push(
            `${i18n("marketplace.browse.integer_min")} ${field.minValue}`
          );
        }
        if (field.maxValue !== "") {
          parts.push(
            `${i18n("marketplace.browse.integer_max")} ${field.maxValue}`
          );
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
    this.loading = true;
    try {
      const params = { page, sort: this.sort };
      if (this.categoryId) {
        params.category_id = this.categoryId;
      }
      if (this.query) {
        params.q = this.query;
      }
      this.addStructuredFilters(params);

      const result = await ajax("/marketplace/listings", { data: params });

      this.listings =
        page === 1 ? result.listings : [...this.listings, ...result.listings];
      this.hasMore = result.pagination.has_more;
      this.page = result.pagination.page;
    } finally {
      this.loading = false;
    }
  }

  @action
  updateQuery(event) {
    this.query = event.target.value;
  }

  @action
  updateCategory(event) {
    this.categoryId = event.target.value ? Number(event.target.value) : "";
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action
  selectCategory(category) {
    this.categoryId =
      Number(this.categoryId) === category.id ? "" : category.id;
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action
  showAllCategories() {
    this.categoryId = "";
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action
  updateSort(event) {
    this.sort = event.target.value;
    this.fetchListings(1);
  }

  @action
  updateStructuredFilter(field, event) {
    this.fieldFilters = {
      ...this.fieldFilters,
      [field.key]: event.target.value,
    };
  }

  @action
  updateIntegerStructuredFilter(field, bound, event) {
    const current = this.fieldFilters[field.key] ?? {};
    this.fieldFilters = {
      ...this.fieldFilters,
      [field.key]: { ...current, [bound]: event.target.value },
    };
  }

  @action
  clearStructuredFilters() {
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action
  clearFilterChip(chip) {
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

  @action
  clearAllFilters() {
    this.query = "";
    this.categoryId = "";
    this.sort = "newest";
    this.fieldFilters = {};
    this.fetchListings(1);
  }

  @action
  search(event) {
    event.preventDefault();
    this.fetchListings(1);
  }

  @action
  loadMore() {
    this.fetchListings(this.page + 1);
  }

  <template>
    <div class="marketplace-browse marketplace-browse--showcase">
      <div class="marketplace-browse__header">
        <div class="marketplace-browse__title-wrap">
          <span class="marketplace-browse__title-icon">{{dIcon "tag"}}</span>
          <h1>{{i18n "marketplace.title"}}</h1>
        </div>
      </div>

      <MarketplaceNav />

      <form class="marketplace-browse__filters" {{on "submit" this.search}}>
        <div class="marketplace-browse__primary-filters">
          <label class="marketplace-browse__search-shell">
            <span class="marketplace-browse__search-icon">{{dIcon
                "magnifying-glass"
              }}</span>
            <input
              type="text"
              class="marketplace-browse__search"
              aria-label={{i18n "marketplace.browse.search_placeholder"}}
              placeholder={{i18n "marketplace.browse.search_placeholder"}}
              value={{this.query}}
              {{on "input" this.updateQuery}}
            />
          </label>

          <select
            class="marketplace-browse__category"
            aria-label={{i18n "marketplace.browse.category_all"}}
            {{on "change" this.updateCategory}}
          >
            <option value="">{{i18n "marketplace.browse.category_all"}}</option>
            {{#each @categories as |category|}}
              <option
                value={{category.id}}
                selected={{eq category.id this.categoryId}}
              >{{category.name}}</option>
            {{/each}}
          </select>

          <select
            class="marketplace-browse__sort"
            aria-label={{i18n "marketplace.browse.sort_label"}}
            {{on "change" this.updateSort}}
          >
            {{#each this.sorts as |sortOption|}}
              <option
                value={{sortOption.value}}
                selected={{eq sortOption.value this.sort}}
              >{{sortOption.label}}</option>
            {{/each}}
          </select>

          <button
            type="submit"
            class="btn btn-primary marketplace-browse__search-button"
            disabled={{this.loading}}
          >
            {{dIcon "magnifying-glass"}}
            <span>{{i18n "marketplace.browse.search_button"}}</span>
          </button>
        </div>

        <div class="marketplace-browse__filter-chips">
          <button
            type="button"
            class={{if
              this.hasActiveFilters
              "marketplace-browse__filter-chip"
              "marketplace-browse__filter-chip marketplace-browse__filter-chip--active"
            }}
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
            <button
              type="button"
              class="btn btn-flat marketplace-browse__clear-all-filters"
              disabled={{this.loading}}
              {{on "click" this.clearAllFilters}}
            >
              {{i18n "marketplace.browse.clear_filters"}}
            </button>
          {{/if}}
        </div>

        {{#if this.structuredFiltersForForm.length}}
          <section class="marketplace-browse__dynamic-filters">
            <div class="marketplace-browse__dynamic-filters-header">
              <h2>{{i18n "marketplace.browse.dynamic_filters"}}</h2>
              <button
                type="button"
                class="btn btn-flat marketplace-browse__clear-filters"
                disabled={{this.loading}}
                {{on "click" this.clearStructuredFilters}}
              >
                {{i18n "marketplace.browse.clear_filters"}}
              </button>
            </div>

            <div class="marketplace-browse__dynamic-filter-grid">
              {{#each this.structuredFiltersForForm as |field|}}
                <div
                  class="marketplace-browse__dynamic-filter"
                  data-filter-key={{field.key}}
                >
                  <label class="marketplace-browse__dynamic-filter-label">
                    {{field.label}}
                  </label>

                  {{#if (eq field.type "integer")}}
                    <div class="marketplace-browse__integer-range">
                      <label>
                        <span>{{i18n "marketplace.browse.integer_min"}}</span>
                        <input
                          type="number"
                          step="1"
                          value={{field.minValue}}
                          {{on
                            "input"
                            (fn this.updateIntegerStructuredFilter field "min")
                          }}
                        />
                      </label>
                      <label>
                        <span>{{i18n "marketplace.browse.integer_max"}}</span>
                        <input
                          type="number"
                          step="1"
                          value={{field.maxValue}}
                          {{on
                            "input"
                            (fn this.updateIntegerStructuredFilter field "max")
                          }}
                        />
                      </label>
                    </div>
                  {{else if (eq field.type "select")}}
                    <select
                      {{on "change" (fn this.updateStructuredFilter field)}}
                    >
                      <option value="">{{i18n
                          "marketplace.browse.filter_any"
                        }}</option>
                      {{#each field.choices as |choice|}}
                        <option
                          value={{choice.value}}
                          selected={{eq choice.value field.value}}
                        >{{choice.label}}</option>
                      {{/each}}
                    </select>
                  {{else if (eq field.type "boolean")}}
                    <select
                      {{on "change" (fn this.updateStructuredFilter field)}}
                    >
                      <option value="">{{i18n
                          "marketplace.browse.filter_any"
                        }}</option>
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
                      value={{field.value}}
                      placeholder={{i18n
                        "marketplace.browse.text_filter_placeholder"
                      }}
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
            <button
              type="button"
              class="btn btn-flat marketplace-browse__section-link"
              disabled={{this.loading}}
              {{on "click" this.showAllCategories}}
            >
              {{i18n "marketplace.browse.view_all_categories"}}
            </button>
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
                disabled={{this.loading}}
                {{on "click" (fn this.selectCategory category)}}
              >
                <span class="marketplace-browse__category-card-icon">
                  {{dIcon "tag"}}
                </span>
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
        <section class="marketplace-browse__featured">
          <div class="marketplace-browse__section-heading">
            <h2>{{i18n "marketplace.browse.featured_listings"}}</h2>
            {{#if this.latestListings.length}}
              <a
                href="#marketplace-latest-listings"
                class="btn btn-flat marketplace-browse__section-link"
              >
                {{i18n "marketplace.browse.view_all_listings"}}
              </a>
            {{/if}}
          </div>

          <div class="marketplace-listings-grid marketplace-browse__featured-grid">
            {{#each this.featuredListings as |listing|}}
              <MarketplaceListingCard @listing={{listing}} />
            {{/each}}
          </div>
        </section>

        {{#if this.latestListings.length}}
          <section
            id="marketplace-latest-listings"
            class="marketplace-browse__latest"
          >
            <div class="marketplace-browse__section-heading">
              <h2>{{i18n "marketplace.browse.latest_listings"}}</h2>
            </div>

            <div class="marketplace-browse__latest-list">
              {{#each this.latestListings as |listing|}}
                <MarketplaceListingCard @listing={{listing}} />
              {{/each}}
            </div>
          </section>
        {{/if}}

        {{#if this.hasMore}}
          <button
            type="button"
            class="btn marketplace-browse__load-more"
            disabled={{this.loading}}
            {{on "click" this.loadMore}}
          >
            {{i18n "marketplace.browse.load_more"}}
          </button>
        {{/if}}
      {{else}}
        <p class="marketplace-browse__empty">{{i18n "marketplace.browse.empty"}}</p>
      {{/if}}
    </div>
  </template>
}
