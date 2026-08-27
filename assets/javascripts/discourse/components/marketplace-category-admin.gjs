import { fn } from "@ember/helper";
import { action } from "@ember/object";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import { i18n } from "discourse-i18n";

export default class MarketplaceCategoryAdmin extends Component {
  @tracked categories = this.args.initialCategories;
  @tracked newName = "";
  @tracked newSlug = "";
  @tracked newPosition = 0;
  @tracked newEnabled = true;
  @tracked savingId = null;
  @tracked creating = false;
  @tracked errorMessage = null;

  errorFor(error) {
    return (
      error.jqXHR?.responseJSON?.errors?.join(", ") ||
      i18n("marketplace.admin.categories.error")
    );
  }

  @action
  updateNew(field, event) {
    const value =
      field === "newEnabled"
        ? event.target.checked
        : field === "newPosition"
          ? Number(event.target.value)
          : event.target.value;
    this[field] = value;
  }

  @action
  updateCategory(categoryId, field, event) {
    const value =
      field === "enabled"
        ? event.target.checked
        : field === "position"
          ? Number(event.target.value)
          : event.target.value;

    this.categories = this.categories.map((category) =>
      category.id === categoryId ? { ...category, [field]: value } : category
    );
  }

  @action
  async createCategory() {
    this.creating = true;
    this.errorMessage = null;

    try {
      const result = await ajax("/marketplace/admin/categories", {
        type: "POST",
        data: {
          name: this.newName,
          slug: this.newSlug,
          position: this.newPosition,
          enabled: this.newEnabled,
        },
      });

      this.categories = [...this.categories, result.category].sort(
        (left, right) => left.position - right.position || left.id - right.id
      );
      this.newName = "";
      this.newSlug = "";
      this.newPosition = 0;
      this.newEnabled = true;
    } catch (error) {
      this.errorMessage = this.errorFor(error);
    } finally {
      this.creating = false;
    }
  }

  @action
  async saveCategory(category) {
    this.savingId = category.id;
    this.errorMessage = null;

    try {
      const result = await ajax(
        `/marketplace/admin/categories/${category.id}`,
        {
          type: "PUT",
          data: {
            name: category.name,
            slug: category.slug,
            position: category.position,
            enabled: category.enabled,
          },
        }
      );

      this.categories = this.categories
        .map((item) =>
          item.id === result.category.id ? result.category : item
        )
        .sort(
          (left, right) => left.position - right.position || left.id - right.id
        );
    } catch (error) {
      this.errorMessage = this.errorFor(error);
    } finally {
      this.savingId = null;
    }
  }

  <template>
    <div class="marketplace-category-admin admin-detail">
      <DPageSubheader
        @titleLabel={{i18n "marketplace.admin.categories.title"}}
        @descriptionLabel={{i18n "marketplace.admin.categories.description"}}
      />

      {{#if this.errorMessage}}
        <div class="alert alert-error" role="alert">{{this.errorMessage}}</div>
      {{/if}}

      <section class="marketplace-category-admin__new">
        <h3>{{i18n "marketplace.admin.categories.new_title"}}</h3>
        <div class="control-group">
          <label>
            {{i18n "marketplace.admin.categories.name"}}
            <input
              class="marketplace-category-admin__new-name"
              type="text"
              maxlength="100"
              value={{this.newName}}
              {{on "input" (fn this.updateNew "newName")}}
            />
          </label>
          <label>
            {{i18n "marketplace.admin.categories.slug"}}
            <input
              class="marketplace-category-admin__new-slug"
              type="text"
              maxlength="100"
              value={{this.newSlug}}
              {{on "input" (fn this.updateNew "newSlug")}}
            />
          </label>
          <label>
            {{i18n "marketplace.admin.categories.position"}}
            <input
              class="marketplace-category-admin__new-position"
              type="number"
              min="0"
              value={{this.newPosition}}
              {{on "input" (fn this.updateNew "newPosition")}}
            />
          </label>
          <label class="marketplace-category-admin__enabled">
            <input
              class="marketplace-category-admin__new-enabled"
              type="checkbox"
              checked={{this.newEnabled}}
              {{on "change" (fn this.updateNew "newEnabled")}}
            />
            {{i18n "marketplace.admin.categories.enabled"}}
          </label>
          <DButton
            class="btn-primary"
            @label="marketplace.admin.categories.create"
            @icon="plus"
            @action={{this.createCategory}}
            @disabled={{this.creating}}
          />
        </div>
      </section>

      {{#if this.categories.length}}
        <table class="d-table marketplace-category-admin__table">
          <thead class="d-table__header">
            <tr>
              <th>{{i18n "marketplace.admin.categories.name"}}</th>
              <th>{{i18n "marketplace.admin.categories.slug"}}</th>
              <th>{{i18n "marketplace.admin.categories.position"}}</th>
              <th>{{i18n "marketplace.admin.categories.enabled"}}</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {{#each this.categories as |category|}}
              <tr class="d-table__row" data-category-id={{category.id}}>
                <td class="d-table__cell">
                  <input
                    class="marketplace-category-admin__name"
                    type="text"
                    maxlength="100"
                    value={{category.name}}
                    aria-label={{i18n "marketplace.admin.categories.name"}}
                    {{on
                      "input"
                      (fn this.updateCategory category.id "name")
                    }}
                  />
                </td>
                <td class="d-table__cell">
                  <input
                    class="marketplace-category-admin__slug"
                    type="text"
                    maxlength="100"
                    value={{category.slug}}
                    aria-label={{i18n "marketplace.admin.categories.slug"}}
                    {{on
                      "input"
                      (fn this.updateCategory category.id "slug")
                    }}
                  />
                </td>
                <td class="d-table__cell">
                  <input
                    class="marketplace-category-admin__position"
                    type="number"
                    min="0"
                    value={{category.position}}
                    aria-label={{i18n "marketplace.admin.categories.position"}}
                    {{on
                      "input"
                      (fn this.updateCategory category.id "position")
                    }}
                  />
                </td>
                <td class="d-table__cell">
                  <input
                    class="marketplace-category-admin__row-enabled"
                    type="checkbox"
                    checked={{category.enabled}}
                    aria-label={{i18n "marketplace.admin.categories.enabled"}}
                    {{on
                      "change"
                      (fn this.updateCategory category.id "enabled")
                    }}
                  />
                </td>
                <td class="d-table__cell-controls">
                  <DButton
                    class="btn-primary btn-small"
                    @label="marketplace.admin.categories.save"
                    @icon="check"
                    @action={{fn this.saveCategory category}}
                    @disabled={{this.savingId}}
                  />
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      {{else}}
        <div class="admin-plugin-config-area__empty-list">
          {{i18n "marketplace.admin.categories.empty"}}
        </div>
      {{/if}}
    </div>
  </template>
}
