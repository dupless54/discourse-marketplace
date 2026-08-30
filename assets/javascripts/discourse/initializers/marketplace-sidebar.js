import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  api.addSidebarSection(
    (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
      class MarketplaceSectionLink extends BaseCustomSidebarSectionLink {
        get name() {
          return "marketplace";
        }

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
