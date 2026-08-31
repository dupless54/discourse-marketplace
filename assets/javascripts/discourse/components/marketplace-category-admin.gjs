import { concat, fn } from "@ember/helper";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import { i18n } from "discourse-i18n";

const FIELD_TYPES = ["text", "textarea", "integer", "boolean", "select"];

function blankField() {
  return {
    key: "",
    label: "",
    type: "text",
    required: false,
    enabled: true,
    position: 0,
    placeholder: "",
    help_text: "",
    choicesText: "",
  };
}

function choicesToText(choices = []) {
  return choices
    .map((choice) => `${choice.value} | ${choice.label}`)
    .join("\n");
}

function textToChoices(text) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const separator = line.indexOf("|");
      return separator === -1
        ? { value: line, label: line }
        : {
            value: line.slice(0, separator).trim(),
            label: line.slice(separator + 1).trim(),
          };
    });
}

export default class MarketplaceCategoryAdmin extends Component {
  @service dialog;

  fieldTypes = FIELD_TYPES;
  @tracked categories = this.args.initialCategories.map((category) =>
    this.prepareCategory(category)
  );
  @tracked newName = "";
  @tracked newSlug = "";
  @tracked newPosition = 0;
  @tracked newEnabled = true;
  @tracked savingId = null;
  @tracked deletingId = null;
  @tracked savingFieldId = null;
  @tracked creatingFieldFor = null;
  @tracked creating = false;
  @tracked errorMessage = null;

  prepareCategory(category) {
    return {
      ...category,
      field_definitions: (category.field_definitions ?? []).map((field) => ({
        ...field,
        choicesText: choicesToText(field.choices),
      })),
      newField: blankField(),
    };
  }

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
  updateNewField(categoryId, field, event) {
    const value =
      field === "required" || field === "enabled"
        ? event.target.checked
        : field === "position"
          ? Number(event.target.value)
          : event.target.value;
    this.categories = this.categories.map((category) =>
      category.id === categoryId
        ? { ...category, newField: { ...category.newField, [field]: value } }
        : category
    );
  }

  @action
  updateField(categoryId, fieldId, property, event) {
    const value =
      property === "required" || property === "enabled"
        ? event.target.checked
        : property === "position"
          ? Number(event.target.value)
          : event.target.value;
    this.categories = this.categories.map((category) =>
      category.id === categoryId
        ? {
            ...category,
            field_definitions: category.field_definitions.map((field) =>
              field.id === fieldId ? { ...field, [property]: value } : field
            ),
          }
        : category
    );
  }

  fieldPayload(field, includeKey = false) {
    const payload = {
      label: field.label,
      type: field.type,
      required: field.required,
      enabled: field.enabled,
      position: field.position,
      placeholder: field.placeholder,
      help_text: field.help_text,
      choices: field.type === "select" ? textToChoices(field.choicesText) : [],
    };
    if (includeKey) {
      payload.key = field.key;
    }
    return payload;
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
      this.categories = [
        ...this.categories,
        this.prepareCategory(result.category),
      ].sort(
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
          item.id === result.category.id
            ? this.prepareCategory(result.category)
            : item
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

  @action
  deleteCategory(category) {
    return this.dialog.yesNoConfirm({
      message: i18n("marketplace.admin.categories.delete_confirm", {
        name: category.name,
      }),
      didConfirm: async () => {
        this.deletingId = category.id;
        this.errorMessage = null;
        try {
          await ajax(`/marketplace/admin/categories/${category.id}`, {
            type: "DELETE",
          });
          this.categories = this.categories.filter(
            (item) => item.id !== category.id
          );
        } catch (error) {
          this.errorMessage = this.errorFor(error);
        } finally {
          this.deletingId = null;
        }
      },
    });
  }

  @action
  async createField(category) {
    this.creatingFieldFor = category.id;
    this.errorMessage = null;
    try {
      const result = await ajax(
        `/marketplace/admin/categories/${category.id}/fields`,
        { type: "POST", data: this.fieldPayload(category.newField, true) }
      );
      const created = {
        ...result.field_definition,
        choicesText: choicesToText(result.field_definition.choices),
      };
      this.categories = this.categories.map((item) =>
        item.id === category.id
          ? {
              ...item,
              field_definitions: [...item.field_definitions, created].sort(
                (left, right) =>
                  left.position - right.position || left.id - right.id
              ),
              newField: blankField(),
            }
          : item
      );
    } catch (error) {
      this.errorMessage = this.errorFor(error);
    } finally {
      this.creatingFieldFor = null;
    }
  }

  @action
  async saveField(category, field) {
    this.savingFieldId = field.id;
    this.errorMessage = null;
    try {
      const result = await ajax(
        `/marketplace/admin/categories/${category.id}/fields/${field.id}`,
        { type: "PUT", data: this.fieldPayload(field) }
      );
      const saved = {
        ...result.field_definition,
        choicesText: choicesToText(result.field_definition.choices),
      };
      this.categories = this.categories.map((item) =>
        item.id === category.id
          ? {
              ...item,
              field_definitions: item.field_definitions
                .map((candidate) =>
                  candidate.id === saved.id ? saved : candidate
                )
                .sort(
                  (left, right) =>
                    left.position - right.position || left.id - right.id
                ),
            }
          : item
      );
    } catch (error) {
      this.errorMessage = this.errorFor(error);
    } finally {
      this.savingFieldId = null;
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
          <label>{{i18n "marketplace.admin.categories.name"}}<input
              class="marketplace-category-admin__new-name"
              type="text"
              maxlength="100"
              value={{this.newName}}
              {{on "input" (fn this.updateNew "newName")}}
            /></label>
          <label>{{i18n "marketplace.admin.categories.slug"}}<input
              class="marketplace-category-admin__new-slug"
              type="text"
              maxlength="100"
              value={{this.newSlug}}
              {{on "input" (fn this.updateNew "newSlug")}}
            /></label>
          <label>{{i18n "marketplace.admin.categories.position"}}<input
              class="marketplace-category-admin__new-position"
              type="number"
              min="0"
              value={{this.newPosition}}
              {{on "input" (fn this.updateNew "newPosition")}}
            /></label>
          <label class="marketplace-category-admin__enabled"><input
              class="marketplace-category-admin__new-enabled"
              type="checkbox"
              checked={{this.newEnabled}}
              {{on "change" (fn this.updateNew "newEnabled")}}
            />{{i18n "marketplace.admin.categories.enabled"}}</label>
          <DButton
            class="btn-primary"
            @label="marketplace.admin.categories.create"
            @icon="plus"
            @action={{this.createCategory}}
            @disabled={{this.creating}}
          />
        </div>
      </section>

      {{#each this.categories as |category|}}
        <section
          class="marketplace-category-admin__category"
          data-category-id={{category.id}}
        >
          <div class="marketplace-category-admin__category-row">
            <label>{{i18n "marketplace.admin.categories.name"}}<input
                class="marketplace-category-admin__name"
                type="text"
                maxlength="100"
                value={{category.name}}
                {{on "input" (fn this.updateCategory category.id "name")}}
              /></label>
            <label>{{i18n "marketplace.admin.categories.slug"}}<input
                class="marketplace-category-admin__slug"
                type="text"
                maxlength="100"
                value={{category.slug}}
                {{on "input" (fn this.updateCategory category.id "slug")}}
              /></label>
            <label>{{i18n "marketplace.admin.categories.position"}}<input
                class="marketplace-category-admin__position"
                type="number"
                min="0"
                value={{category.position}}
                {{on "input" (fn this.updateCategory category.id "position")}}
              /></label>
            <label class="marketplace-category-admin__enabled"><input
                class="marketplace-category-admin__row-enabled"
                type="checkbox"
                checked={{category.enabled}}
                {{on "change" (fn this.updateCategory category.id "enabled")}}
              />{{i18n "marketplace.admin.categories.enabled"}}</label>
            <DButton
              class="btn-primary btn-small"
              @label="marketplace.admin.categories.save"
              @icon="check"
              @action={{fn this.saveCategory category}}
              @disabled={{this.savingId}}
            />
            <DButton
              class="btn-danger btn-small marketplace-category-admin__delete-category"
              @label="marketplace.admin.categories.delete"
              @icon="trash-can"
              @action={{fn this.deleteCategory category}}
              @disabled={{this.deletingId}}
            />
          </div>

          <div class="marketplace-category-admin__fields">
            <h4>{{i18n "marketplace.admin.categories.fields.title"}}</h4>
            {{#each category.field_definitions as |field|}}
              <div
                class="marketplace-category-admin__field"
                data-field-id={{field.id}}
              >
                <label>{{i18n "marketplace.admin.categories.fields.key"}}<input
                    type="text"
                    value={{field.key}}
                    readonly
                  /></label>
                <label>{{i18n
                    "marketplace.admin.categories.fields.label"
                  }}<input
                    type="text"
                    maxlength="100"
                    class="marketplace-category-admin__field-label"
                    value={{field.label}}
                    {{on
                      "input"
                      (fn this.updateField category.id field.id "label")
                    }}
                  /></label>
                <label>{{i18n
                    "marketplace.admin.categories.fields.type"
                  }}<select
                    class="marketplace-category-admin__field-type"
                    {{on
                      "change"
                      (fn this.updateField category.id field.id "type")
                    }}
                  >{{#each this.fieldTypes as |type|}}<option
                        value={{type}}
                        selected={{eq type field.type}}
                      >{{i18n
                          (concat
                            "marketplace.admin.categories.fields.types." type
                          )
                        }}</option>{{/each}}</select></label>
                <label>{{i18n "marketplace.admin.categories.position"}}<input
                    type="number"
                    min="0"
                    class="marketplace-category-admin__field-position"
                    value={{field.position}}
                    {{on
                      "input"
                      (fn this.updateField category.id field.id "position")
                    }}
                  /></label>
                <label class="marketplace-category-admin__check"><input
                    type="checkbox"
                    class="marketplace-category-admin__field-required"
                    checked={{field.required}}
                    {{on
                      "change"
                      (fn this.updateField category.id field.id "required")
                    }}
                  />{{i18n
                    "marketplace.admin.categories.fields.required"
                  }}</label>
                <label class="marketplace-category-admin__check"><input
                    type="checkbox"
                    class="marketplace-category-admin__field-enabled"
                    checked={{field.enabled}}
                    {{on
                      "change"
                      (fn this.updateField category.id field.id "enabled")
                    }}
                  />{{i18n "marketplace.admin.categories.enabled"}}</label>
                <label>{{i18n
                    "marketplace.admin.categories.fields.placeholder"
                  }}<input
                    type="text"
                    maxlength="150"
                    value={{field.placeholder}}
                    {{on
                      "input"
                      (fn this.updateField category.id field.id "placeholder")
                    }}
                  /></label>
                <label>{{i18n
                    "marketplace.admin.categories.fields.help_text"
                  }}<input
                    type="text"
                    maxlength="500"
                    value={{field.help_text}}
                    {{on
                      "input"
                      (fn this.updateField category.id field.id "help_text")
                    }}
                  /></label>
                {{#if (eq field.type "select")}}
                  <label class="marketplace-category-admin__choices">{{i18n
                      "marketplace.admin.categories.fields.choices"
                    }}<textarea
                      class="marketplace-category-admin__field-choices"
                      rows="3"
                      value={{field.choicesText}}
                      {{on
                        "input"
                        (fn this.updateField category.id field.id "choicesText")
                      }}
                    ></textarea></label>
                {{/if}}
                <DButton
                  class="btn-primary btn-small marketplace-category-admin__save-field"
                  @label="marketplace.admin.categories.fields.save"
                  @icon="check"
                  @action={{fn this.saveField category field}}
                  @disabled={{this.savingFieldId}}
                />
              </div>
            {{else}}
              <p class="marketplace-category-admin__no-fields">{{i18n
                  "marketplace.admin.categories.fields.empty"
                }}</p>
            {{/each}}

            <div
              class="marketplace-category-admin__field marketplace-category-admin__field--new"
            >
              <h5>{{i18n "marketplace.admin.categories.fields.add"}}</h5>
              <label>{{i18n "marketplace.admin.categories.fields.key"}}<input
                  type="text"
                  maxlength="50"
                  class="marketplace-category-admin__new-field-key"
                  value={{category.newField.key}}
                  {{on "input" (fn this.updateNewField category.id "key")}}
                /></label>
              <label>{{i18n "marketplace.admin.categories.fields.label"}}<input
                  type="text"
                  maxlength="100"
                  class="marketplace-category-admin__new-field-label"
                  value={{category.newField.label}}
                  {{on "input" (fn this.updateNewField category.id "label")}}
                /></label>
              <label>{{i18n "marketplace.admin.categories.fields.type"}}<select
                  class="marketplace-category-admin__new-field-type"
                  {{on "change" (fn this.updateNewField category.id "type")}}
                >{{#each this.fieldTypes as |type|}}<option
                      value={{type}}
                      selected={{eq type category.newField.type}}
                    >{{i18n
                        (concat
                          "marketplace.admin.categories.fields.types." type
                        )
                      }}</option>{{/each}}</select></label>
              <label>{{i18n "marketplace.admin.categories.position"}}<input
                  type="number"
                  min="0"
                  value={{category.newField.position}}
                  {{on "input" (fn this.updateNewField category.id "position")}}
                /></label>
              <label class="marketplace-category-admin__check"><input
                  type="checkbox"
                  checked={{category.newField.required}}
                  {{on
                    "change"
                    (fn this.updateNewField category.id "required")
                  }}
                />{{i18n
                  "marketplace.admin.categories.fields.required"
                }}</label>
              <label class="marketplace-category-admin__check"><input
                  type="checkbox"
                  checked={{category.newField.enabled}}
                  {{on "change" (fn this.updateNewField category.id "enabled")}}
                />{{i18n "marketplace.admin.categories.enabled"}}</label>
              <label>{{i18n
                  "marketplace.admin.categories.fields.placeholder"
                }}<input
                  type="text"
                  maxlength="150"
                  value={{category.newField.placeholder}}
                  {{on
                    "input"
                    (fn this.updateNewField category.id "placeholder")
                  }}
                /></label>
              <label>{{i18n
                  "marketplace.admin.categories.fields.help_text"
                }}<input
                  type="text"
                  maxlength="500"
                  value={{category.newField.help_text}}
                  {{on
                    "input"
                    (fn this.updateNewField category.id "help_text")
                  }}
                /></label>
              {{#if (eq category.newField.type "select")}}
                <label class="marketplace-category-admin__choices">{{i18n
                    "marketplace.admin.categories.fields.choices"
                  }}<textarea
                    class="marketplace-category-admin__new-field-choices"
                    rows="3"
                    value={{category.newField.choicesText}}
                    {{on
                      "input"
                      (fn this.updateNewField category.id "choicesText")
                    }}
                  ></textarea></label>
              {{/if}}
              <DButton
                class="btn-primary btn-small marketplace-category-admin__add-field"
                @label="marketplace.admin.categories.fields.add"
                @icon="plus"
                @action={{fn this.createField category}}
                @disabled={{this.creatingFieldFor}}
              />
            </div>
          </div>
        </section>
      {{else}}
        <div class="admin-plugin-config-area__empty-list">
          {{i18n "marketplace.admin.categories.empty"}}
        </div>
      {{/each}}
    </div>
  </template>
}
