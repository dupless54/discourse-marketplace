import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class MarketplaceSellerRoute extends Route {
  async model(params) {
    return ajax(`/marketplace/sellers/${encodeURIComponent(params.username)}`);
  }
}
