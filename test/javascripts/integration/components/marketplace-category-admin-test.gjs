import { click, fillIn, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import DialogHolder from "discourse/dialog-holder/components/dialog-holder";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import MarketplaceCategoryAdmin from "discourse/plugins/discourse-marketplace/discourse/components/marketplace-category-admin";

module("Integration | Component | MarketplaceCategoryAdmin", function (hooks) {
  setupRenderingTest(hooks);

  test("renders enabled and disabled categories for administration", async function (assert) {
    this.categories = [
      {
        id: 1,
        name: "Electronics",
        slug: "electronics",
        position: 1,
        enabled: true,
        field_definitions: [
          {
            id: 10,
            key: "mileage",
            label: "Mileage",
            type: "integer",
            required: true,
            enabled: true,
            position: 1,
            choices: [],
          },
        ],
      },
      {
        id: 2,
        name: "Archived category",
        slug: "archived-category",
        position: 2,
        enabled: false,
        field_definitions: [],
      },
    ];

    await render(
      <template>
        <MarketplaceCategoryAdmin @initialCategories={{this.categories}} />
      </template>
    );

    assert
      .dom(".marketplace-category-admin__new-name")
      .exists("the create form is rendered");
    assert
      .dom("[data-category-id]")
      .exists({ count: 2 }, "all categories are rendered");
    assert
      .dom('[data-category-id="1"] .marketplace-category-admin__row-enabled')
      .isChecked("the enabled category is checked");
    assert
      .dom('[data-category-id="2"] .marketplace-category-admin__row-enabled')
      .isNotChecked("the disabled category remains visible and unchecked");

    await click(".marketplace-category-admin__new-enabled");

    assert
      .dom(".marketplace-category-admin__new-enabled")
      .isNotChecked("the new category enabled state is editable");

    assert.dom('[data-category-id="1"] [data-field-id="10"]').exists();
    assert
      .dom('[data-field-id="10"] input[readonly]')
      .hasValue("mileage", "the stable field key is visible but immutable");
    assert
      .dom('[data-category-id="1"] .marketplace-category-admin__add-field')
      .exists();
  });

  test("adds a select field through the existing category admin", async function (assert) {
    this.categories = [
      {
        id: 1,
        name: "Cars",
        slug: "cars",
        position: 1,
        enabled: true,
        field_definitions: [],
      },
    ];
    pretender.post("/marketplace/admin/categories/1/fields", () =>
      response({
        field_definition: {
          id: 20,
          key: "fuel",
          label: "Fuel",
          type: "select",
          required: true,
          enabled: true,
          position: 1,
          choices: [{ value: "diesel", label: "Diesel" }],
        },
      })
    );

    await render(
      <template>
        <MarketplaceCategoryAdmin @initialCategories={{this.categories}} />
      </template>
    );
    await fillIn(".marketplace-category-admin__new-field-key", "fuel");
    await fillIn(".marketplace-category-admin__new-field-label", "Fuel");
    await fillIn(".marketplace-category-admin__new-field-type", "select");
    await fillIn(
      ".marketplace-category-admin__new-field-choices",
      "diesel | Diesel"
    );
    await click(".marketplace-category-admin__add-field");

    assert.dom('[data-field-id="20"]').exists();
    assert.dom('[data-field-id="20"] input[readonly]').hasValue("fuel");
    assert
      .dom('[data-field-id="20"] .marketplace-category-admin__field-choices')
      .hasValue("diesel | Diesel");
  });

  test("edits, disables, and reorders a field", async function (assert) {
    this.categories = [
      {
        id: 1,
        name: "Cars",
        slug: "cars",
        position: 1,
        enabled: true,
        field_definitions: [
          {
            id: 10,
            key: "mileage",
            label: "Mileage",
            type: "integer",
            required: false,
            enabled: true,
            position: 1,
            choices: [],
          },
        ],
      },
    ];
    pretender.put("/marketplace/admin/categories/1/fields/10", () =>
      response({
        field_definition: {
          id: 10,
          key: "mileage",
          label: "Odometer",
          type: "integer",
          required: true,
          enabled: false,
          position: 4,
          choices: [],
        },
      })
    );

    await render(
      <template>
        <MarketplaceCategoryAdmin @initialCategories={{this.categories}} />
      </template>
    );
    await fillIn(".marketplace-category-admin__field-label", "Odometer");
    await fillIn(".marketplace-category-admin__field-position", "4");
    await click(".marketplace-category-admin__field-required");
    await click(".marketplace-category-admin__field-enabled");
    await click(".marketplace-category-admin__save-field");

    assert.dom(".marketplace-category-admin__field-label").hasValue("Odometer");
    assert.dom(".marketplace-category-admin__field-position").hasValue("4");
    assert.dom(".marketplace-category-admin__field-required").isChecked();
    assert.dom(".marketplace-category-admin__field-enabled").isNotChecked();
  });

  test("deletes an unused category after confirmation", async function (assert) {
    this.categories = [
      {
        id: 1,
        name: "Cars",
        slug: "cars",
        position: 1,
        enabled: true,
        field_definitions: [],
      },
    ];
    pretender.delete("/marketplace/admin/categories/1", () => response({}));

    await render(
      <template>
        <DialogHolder />
        <MarketplaceCategoryAdmin @initialCategories={{this.categories}} />
      </template>
    );

    await click(".marketplace-category-admin__delete-category");

    assert
      .dom(".dialog-body")
      .includesText("Cars", "the confirmation identifies the category");

    await click(".dialog-footer .btn-primary");

    assert
      .dom('[data-category-id="1"]')
      .doesNotExist("the deleted category is removed");
  });
});
