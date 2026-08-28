import { fillIn, render, waitUntil } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { createFile } from "discourse/tests/helpers/qunit-helpers";
import MarketplaceListingForm from "discourse/plugins/discourse-marketplace/discourse/components/marketplace-listing-form";

module("Integration | Component | MarketplaceListingForm", function (hooks) {
  setupRenderingTest(hooks);

  const categories = [{ id: 1, name: "Electronics" }];

  test("shows an upload control when creating a listing", async function (assert) {
    await render(
      <template>
        <MarketplaceListingForm @categories={{categories}} />
      </template>
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
      <template>
        <MarketplaceListingForm @categories={{categories}} />
      </template>
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
      <template>
        <MarketplaceListingForm @categories={{categories}} />
      </template>
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
      <template>
        <MarketplaceListingForm @categories={{categories}} />
      </template>
    );

    assert
      .dom(".marketplace-listing-form__inventory-mode")
      .hasValue("single");
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

    assert
      .dom(".marketplace-listing-form__inventory-mode")
      .hasValue("finite");
    assert
      .dom(".marketplace-listing-form__stock-field input")
      .hasValue("8");
    assert
      .dom(".marketplace-listing-form__expires-field input")
      .hasValue(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/);
  });
});
