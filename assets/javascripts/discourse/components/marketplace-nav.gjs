import Component from "@glimmer/component";
import { service } from "@ember/service";
import DHorizontalOverflowNav from "discourse/ui-kit/d-horizontal-overflow-nav";
import DNavItem from "discourse/ui-kit/d-nav-item";
import { i18n } from "discourse-i18n";

// One compact nav, reused at the top of every top-level Marketplace page
// (Browse, New Listing, My Listings, Transaction Center) instead of each
// page hand-rolling its own header links. DHorizontalOverflowNav is core's
// own mobile-safe scrollable nav shell (see e.g. templates/review/index.gjs)
// -- it already handles narrow-viewport overflow, so there is no custom
// mobile nav framework here. DNavItem's default active-state (no
// `@currentWhen` override) is core's own router.isActive(route) check: each
// of these four routes is a leaf with no children of its own, so exactly
// one item is active at a time and none of them light up on a listing's
// detail/edit page -- the sensible default for pages that aren't part of
// this tab set (they get their own "back to Marketplace" link instead, see
// marketplace-listing-detail.gjs).
export default class MarketplaceNav extends Component {
  @service currentUser;

  <template>
    <DHorizontalOverflowNav
      @ariaLabel={{i18n "marketplace.nav.aria_label"}}
      class="marketplace-nav"
    >
      <DNavItem @route="marketplace.index" @label="marketplace.title" @icon="tag" />
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
          @route="marketplace.transactions"
          @label="marketplace.my_transactions"
          @icon="right-left"
        />
      {{/if}}
    </DHorizontalOverflowNav>
  </template>
}
