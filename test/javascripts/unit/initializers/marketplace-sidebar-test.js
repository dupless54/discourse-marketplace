import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import {
  customPanels,
  resetSidebarPanels,
} from "discourse/lib/sidebar/custom-sections";
import marketplaceSidebar from "discourse/plugins/discourse-marketplace/discourse/initializers/marketplace-sidebar";

function mainPanel() {
  return customPanels.find((panel) => panel.key === "main");
}

function marketplaceSections() {
  // panel.sections holds the raw, uninstantiated classes returned from the
  // addSidebarSection callback -- core only calls `new` on them lazily, at
  // sidebar render time (see components/sidebar/api-sections.gjs). Reading
  // `.name` off the class itself would return the JS Function.name (the
  // class's own declared identifier), not our custom getter, so instantiate
  // first, exactly as the real render path does.
  return mainPanel()
    .sections.map((Section) => new Section())
    .filter((section) => section.name === "marketplace");
}

module("Unit | Initializer | marketplace-sidebar", function (hooks) {
  setupTest(hooks);

  hooks.afterEach(function () {
    // addSidebarSection pushes into a module-level registry that otherwise
    // outlives this test file for the rest of the QUnit run.
    resetSidebarPanels();
  });

  test("registers exactly one Marketplace section on the main sidebar panel", function (assert) {
    marketplaceSidebar.initialize(this.owner);

    const sections = marketplaceSections();
    assert.strictEqual(
      sections.length,
      1,
      "no duplicate Marketplace sidebar section is registered"
    );

    const [section] = sections;
    assert.strictEqual(section.links.length, 1);

    const [link] = section.links;
    assert.strictEqual(link.route, "marketplace");
    assert.strictEqual(link.prefixType, "icon");
    assert.strictEqual(link.prefixValue, "tag");
    assert.true(link.title.length > 0);
    assert.true(link.text.length > 0);
  });
});
