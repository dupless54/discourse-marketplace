import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

// api.addSidebarSection is the current, documented API for a plugin adding
// its own persistent top-level sidebar entry (see plugin-api.gjs; the same
// mechanism the bundled chat plugin uses for its own sidebar presence).
// api.addCommunitySectionLink was considered too -- it only offers a link
// tucked behind the Community section's "More…" drawer, not a first-class
// entry point, so it doesn't fit "feels like a native Discourse section."
//
// No site-setting check is needed here: `enabled_site_setting
// :marketplace_enabled` in plugin.rb already keeps this plugin's entire JS
// bundle -- this initializer included -- from being served to the client
// at all while the setting is off (verified from
// Plugin::Instance#enabled?/asset serving in Discourse core), so the
// section can only ever register while Marketplace is actually enabled.
export default {
  name: "marketplace-sidebar",

  initialize() {
    withPluginApi((api) => {
      api.addSidebarSection(
        (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
          class MarketplaceSectionLink extends BaseCustomSidebarSectionLink {
            get name() {
              return "marketplace";
            }

            // The bare parent route, not "marketplace.index": Ember's
            // built-in route-hierarchy active-check (the same one
            // <LinkTo> and RouterService#isActive use) then treats every
            // nested Marketplace route -- new/mine/transactions/a listing
            // and its edit page -- as "within" this link, so the sidebar
            // entry stays highlighted anywhere in the section without a
            // hand-maintained list of route names.
            get route() {
              return "marketplace";
            }

            get title() {
              return i18n("marketplace.title");
            }

            get text() {
              return i18n("marketplace.title");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "tag";
            }
          }

          return class MarketplaceSection extends BaseCustomSidebarSection {
            get name() {
              return "marketplace";
            }

            get text() {
              return i18n("marketplace.title");
            }

            get links() {
              return [new MarketplaceSectionLink()];
            }
          };
        }
      );
    });
  },
};
