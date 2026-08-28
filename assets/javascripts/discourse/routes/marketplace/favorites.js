import Route from "@ember/routing/route";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class MarketplaceFavoritesRoute extends Route {
  @service currentUser;
  @service router;

  beforeModel() {
    if (!this.currentUser) {
      this.router.transitionTo("marketplace.index");
    }
  }

  async model() {
    const result = await ajax("/marketplace/favorites");
    return { listingsResult: result };
  }
}
