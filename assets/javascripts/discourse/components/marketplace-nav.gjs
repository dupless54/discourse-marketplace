import Component from "@glimmer/component";
import { service } from "@ember/service";
import DHorizontalOverflowNav from "discourse/ui-kit/d-horizontal-overflow-nav";
import DNavItem from "discourse/ui-kit/d-nav-item";
import { i18n } from "discourse-i18n";

// One compact nav, reused at the top of every top-level Marketplace page.
// The outer shell prevents the scrollable core nav from contributing its
// intrinsic item width to the document on narrow viewports.
export default class MarketplaceNav extends Component {
  @service currentUser;

  <template>
    <div class="marketplace-nav-shell">
      <DHorizontalOverflowNav
        @ariaLabel={{i18n "marketplace.nav.aria_label"}}
        class="marketplace-nav"
      >
        <DNavItem
          @route="marketplace.index"
          @label="marketplace.title"
          @icon="tag"
        />
        {{#if this.currentUser}}
          <DNavItem
            @route="marketplace.new"
            @label="marketplace.new_listing"
            @icon="plus"
          />
          <DNavItem
            @route="marketplace.mine"
            @label="marketplace.my_listings"
            @icon="list"
          />
          <DNavItem
            @route="marketplace.favorites"
            @label="marketplace.favorites.title"
            @icon="heart"
          />
          <DNavItem
            @route="marketplace.offers"
            @label="marketplace.offers.title"
            @icon="handshake"
          />
          <DNavItem
            @route="marketplace.transactions"
            @label="marketplace.my_transactions"
            @icon="right-left"
          />
        {{/if}}
      </DHorizontalOverflowNav>
    </div>
  </template>
}
