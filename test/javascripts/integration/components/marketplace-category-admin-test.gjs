import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import MarketplaceCategoryAdmin from "discourse/plugins/discourse-marketplace/admin/components/marketplace-category-admin";

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
      },
      {
        id: 2,
        name: "Archived category",
        slug: "archived-category",
        position: 2,
        enabled: false,
      },
    ];

    await render(<template>
      <MarketplaceCategoryAdmin @initialCategories={{this.categories}} />
    </template>);

    assert.dom(".marketplace-category-admin__new-name").exists("the create form is rendered");
    assert.dom("[data-category-id]").exists({ count: 2 }, "all categories are rendered");
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
  });
});
