import Route from "@ember/routing/route";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class MarketplaceTransactionsRoute extends Route {
  @service currentUser;
  @service router;

  beforeModel() {
    if (!this.currentUser) {
      this.router.transitionTo("marketplace.index");
    }
  }

  async model() {
    const result = await ajax("/marketplace/transactions/mine", {
      data: { role: "buyer", page: 1 },
    });
    return { initialRole: "buyer", initialResult: result };
  }
}
