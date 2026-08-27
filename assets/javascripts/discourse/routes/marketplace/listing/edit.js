import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class MarketplaceListingEditRoute extends Route {
  async model() {
    const { listing } = this.modelFor("marketplace.listing");
    const categoriesResult = await ajax("/marketplace/categories");
    return { listing, categories: categoriesResult.categories };
  }
}
