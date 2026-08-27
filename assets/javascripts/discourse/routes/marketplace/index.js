import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class MarketplaceIndexRoute extends Route {
  async model() {
    const [categoriesResult, listingsResult] = await Promise.all([
      ajax("/marketplace/categories"),
      ajax("/marketplace/listings"),
    ]);

    return {
      categories: categoriesResult.categories,
      listingsResult,
    };
  }
}
