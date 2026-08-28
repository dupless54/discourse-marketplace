import Route from "@ember/routing/route";

export default class MarketplaceListingIndexRoute extends Route {
  model() {
    return this.modelFor("marketplace.listing");
  }
}
