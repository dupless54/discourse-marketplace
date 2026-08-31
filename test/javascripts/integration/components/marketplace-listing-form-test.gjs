import { fillIn, render, waitUntil } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { createFile } from "discourse/tests/helpers/qunit-helpers";
import MarketplaceListingForm from "discourse/plugins/discourse-marketplace/discourse/components/marketplace-listing-form";

module("Integration | Component | MarketplaceListingForm", function (hooks) {
  setupRenderingTest(hooks);

  const categories = [{ id: 1, name: "Electronics" }];

  const structuredCategories = [
    {
      id: 1,
      name: "Cars",
      field_definitions: [
        {
          key: "model",
          label: "Model",
          type: "text",
          required: true,
          choices: [],
        },
        {
          key: "notes",
          label: "Notes",
          type: "textarea",
          required: false,
          choices: [],
        },
        {
          key: "mileage",
          label: "Mileage",
          type: "integer",
          required: true,
          choices: [],
        },
        {
          key: "trade_available",
          label: "Trade available",
          type: "boolean",
          required: false,
          choices: [],
        },
        {
          key: "fuel",
          label: "Fuel",
          type: "select",
          required: true,
          choices: [
            { value: "diesel", label: "Diesel" },
            { value: "electric", label: "Electric" },
          ],
        },
      ],
    },
    {
      id: 2,
      name: "Digital",
      field_definitions: [
        {
          key: "platform",
          label: "Platform",
          type: "select",
          required: true,
          choices: [{ value: "steam", label: "Steam" }],
        },
      ],
    },
  ];

  test("shows an upload control when creating a listing", async function (assert) {
    await render(
      <template><MarketplaceListingForm @categories={{categories}} /></template>
    );

    assert
      .dom(".marketplace-listing-form__upload-button")
      .exists("the upload button is shown");
    assert
      .dom(".marketplace-listing-form__upload-input")
      .exists("a file input is registered for the uploader");
    assert
      .dom(".marketplace-listing-form__upload-input")
      .hasClass(
        "hidden-upload-field",
        "the native file input is visually hidden, not shown duplicated next to the upload button"
      );
  });

  test("shows an upload control and the existing description when editing a listing", async function (assert) {
    const listing = {
      id: 5,
      title: "Existing listing",
      raw: "An existing description",
      category_id: 1,
      price_cents: 500,
      currency: "USD",
    };

    await render(
      <template>
        <MarketplaceListingForm
          @categories={{categories}}
          @listing={{listing}}
        />
      </template>
    );

    assert
      .dom(".marketplace-listing-form__upload-button")
      .exists("the upload button is shown when editing");
    assert
      .dom("textarea")
      .hasValue(
        "An existing description",
        "the existing raw description is preserved"
      );
  });

  test("still supports a plain text-only description with no uploads", async function (assert) {
    await render(
      <template><MarketplaceListingForm @categories={{categories}} /></template>
    );

    await fillIn("textarea", "Just a plain text description");

    assert
      .dom("textarea")
      .hasValue(
        "Just a plain text description",
        "typing directly into the description still works"
      );
  });

  test("appends the returned upload:// markdown to the description on a successful upload", async function (assert) {
    pretender.post("/uploads.json", () =>
      response({
        id: 42,
        original_filename: "listing-photo.png",
        url: "/uploads/default/original/listing-photo.png",
        short_url: "upload://abc123.png",
        thumbnail_width: 100,
        thumbnail_height: 80,
      })
    );

    await render(
      <template><MarketplaceListingForm @categories={{categories}} /></template>
    );

    await this.container
      .lookup("service:app-events")
      .trigger("upload-mixin:marketplace-listing-upload:add-files", [
        createFile("listing-photo.png"),
      ]);

    await waitUntil(() =>
      document.querySelector("textarea")?.value.includes("upload://abc123.png")
    );

    assert
      .dom("textarea")
      .hasValue(
        /upload:\/\/abc123\.png/,
        "the uploaded file's markdown is inserted into the description"
      );
  });

  test("defaults to single and hides the stock field, showing it once Stoklu/finite is selected", async function (assert) {
    await render(
      <template><MarketplaceListingForm @categories={{categories}} /></template>
    );

    assert.dom(".marketplace-listing-form__inventory-mode").hasValue("single");
    assert.dom(".marketplace-listing-form__stock-field").doesNotExist();

    await fillIn(".marketplace-listing-form__inventory-mode", "finite");

    assert.dom(".marketplace-listing-form__stock-field").exists();

    await fillIn(".marketplace-listing-form__inventory-mode", "unlimited");

    assert.dom(".marketplace-listing-form__stock-field").doesNotExist();
  });

  test("pre-fills inventory mode, stock quantity, and expiration when editing an existing finite listing", async function (assert) {
    const listing = {
      id: 7,
      title: "Existing finite listing",
      raw: "A limited run item",
      category_id: 1,
      price_cents: 500,
      currency: "USD",
      inventory_mode: "finite",
      stock_quantity: 8,
      expires_at: "2030-01-15T10:30:00.000Z",
    };

    await render(
      <template>
        <MarketplaceListingForm
          @categories={{categories}}
          @listing={{listing}}
        />
      </template>
    );

    assert.dom(".marketplace-listing-form__inventory-mode").hasValue("finite");
    assert.dom(".marketplace-listing-form__stock-field input").hasValue("8");
    assert
      .dom(".marketplace-listing-form__expires-field input")
      .hasValue(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/);
  });

  test("renders every supported field type when a category is selected", async function (assert) {
    await render(
      <template>
        <MarketplaceListingForm @categories={{structuredCategories}} />
      </template>
    );

    assert.dom(".marketplace-listing-form__structured-fields").doesNotExist();
    await fillIn(".marketplace-listing-form__category", "1");

    assert.dom('[data-field-key="model"] input[type="text"]').exists();
    assert.dom('[data-field-key="notes"] textarea').exists();
    assert.dom('[data-field-key="mileage"] input[type="number"]').exists();
    assert
      .dom('[data-field-key="trade_available"] input[type="checkbox"]')
      .exists();
    assert.dom('[data-field-key="fuel"] select').exists();
    assert.dom(".marketplace-listing-form__required").exists({ count: 3 });
  });

  test("switching category replaces fields without leaking same-category state", async function (assert) {
    await render(
      <template>
        <MarketplaceListingForm @categories={{structuredCategories}} />
      </template>
    );

    await fillIn(".marketplace-listing-form__category", "1");
    await fillIn('[data-field-key="model"] input', "BMW 320d");
    await fillIn(".marketplace-listing-form__category", "2");

    assert.dom('[data-field-key="model"]').doesNotExist();
    assert.dom('[data-field-key="mileage"]').doesNotExist();
    assert.dom('[data-field-key="platform"] select').exists();
    assert.dom('[data-field-key="platform"] select').hasValue("");
  });

  test("preloads existing structured values on edit", async function (assert) {
    const listing = {
      id: 8,
      title: "BMW 320d",
      raw: "Car description",
      category_id: 1,
      price_cents: 500,
      currency: "USD",
      custom_fields: [
        { key: "model", type: "text", value: "BMW 320d" },
        { key: "mileage", type: "integer", value: "125000" },
        { key: "trade_available", type: "boolean", value: "true" },
        { key: "fuel", type: "select", value: "diesel" },
      ],
    };

    await render(
      <template>
        <MarketplaceListingForm
          @categories={{structuredCategories}}
          @listing={{listing}}
        />
      </template>
    );

    assert.dom('[data-field-key="model"] input').hasValue("BMW 320d");
    assert.dom('[data-field-key="mileage"] input').hasValue("125000");
    assert.dom('[data-field-key="trade_available"] input').isChecked();
    assert.dom('[data-field-key="fuel"] select').hasValue("diesel");
  });
});
