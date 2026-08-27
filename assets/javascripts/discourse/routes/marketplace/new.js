import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class MarketplaceNewRoute extends Route {
  async model() {
    const result = await ajax("/marketplace/categories");
    return { categories: result.categories };
  }
}
