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
});
