import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-marketplace";

export default {
  name: "marketplace-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "marketplace.admin.categories.short_title",
          route: "adminPlugins.show.marketplace-categories",
          description: "marketplace.admin.categories.description",
        },
      ]);
    });
  },
};
