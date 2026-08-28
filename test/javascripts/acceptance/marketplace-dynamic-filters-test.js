import { click, fillIn, select, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const CATEGORY = {
  id: 3,
  name: "Games",
  slug: "games",
  position: 0,
  field_definitions: [
    {
      key: "platform",
      label: "Platform",
      type: "select",
      required: false,
      position: 0,
      choices: [
        { value: "steam", label: "Steam" },
        { value: "epic", label: "Epic" },
      ],
      placeholder: null,
      help_text: null,
    },
    {
      key: "score",
      label: "Score",
      type: "integer",
      required: false,
      position: 1,
      choices: [],
      placeholder: null,
      help_text: null,
    },
    {
      key: "warranty",
      label: "Warranty",
      type: "boolean",
      required: false,
      position: 2,
      choices: [],
      placeholder: null,
      help_text: null,
    },
    {
      key: "edition",
      label: "Edition",
      type: "text",
      required: false,
      position: 3,
      choices: [],
      placeholder: null,
      help_text: null,
    },
  ],
};

const EMPTY_LISTINGS = {
  listings: [],
  pagination: { page: 1, per_page: 20, has_more: false },
};

const scoreMin = '[data-filter-key="score"] .marketplace-browse__integer-range label:first-child input';
const scoreMax = '[data-filter-key="score"] .marketplace-browse__integer-range label:last-child input';

acceptance("Marketplace | dynamic filters", function (needs) {
  let listingRequests;

  needs.settings({ marketplace_enabled: true });
  needs.pretender((server, helper) => {
    listingRequests = [];

    server.get("/marketplace/categories", () =>
      helper.response({ categories: [CATEGORY] })
    );
    server.get("/marketplace/listings", (request) => {
      listingRequests.push({ ...request.queryParams });
      return helper.response(EMPTY_LISTINGS);
    });
  });

  test("builds filters from the selected category and sends them with browse requests", async function (assert) {
    await visit("/marketplace");

    assert.dom(".marketplace-browse__dynamic-filters").doesNotExist();

    await select(".marketplace-browse__category", "3");

    assert.dom(".marketplace-browse__dynamic-filters").exists();
    assert.dom('[data-filter-key="platform"] select').exists();
    assert.dom('[data-filter-key="score"] input').exists({ count: 2 });
    assert.dom('[data-filter-key="warranty"] select').exists();
    assert.dom('[data-filter-key="edition"] input').exists();

    await select('[data-filter-key="platform"] select', "steam");
    await fillIn(scoreMin, "5");
    await fillIn(scoreMax, "20");
    await select('[data-filter-key="warranty"] select', "true");
    await fillIn('[data-filter-key="edition"] input', "collector");
    await click(".marketplace-browse__primary-filters .btn-primary");

    const request = listingRequests.at(-1);
    assert.strictEqual(request.category_id, "3");
    assert.strictEqual(request["field_filters[platform]"], "steam");
    assert.strictEqual(request["field_filters[score][min]"], "5");
    assert.strictEqual(request["field_filters[score][max]"], "20");
    assert.strictEqual(request["field_filters[warranty]"], "true");
    assert.strictEqual(request["field_filters[edition]"], "collector");
  });

  test("clears category-derived filters without leaking them into the next request", async function (assert) {
    await visit("/marketplace");
    await select(".marketplace-browse__category", "3");
    await select('[data-filter-key="platform"] select', "steam");
    await fillIn(scoreMin, "5");

    await click(".marketplace-browse__clear-filters");

    assert.dom('[data-filter-key="platform"] select').hasValue("");
    assert.dom(scoreMin).hasValue("");

    const request = listingRequests.at(-1);
    assert.strictEqual(request.category_id, "3");
    assert.notOk(request["field_filters[platform]"]);
    assert.notOk(request["field_filters[score][min]"]);
  });
});
