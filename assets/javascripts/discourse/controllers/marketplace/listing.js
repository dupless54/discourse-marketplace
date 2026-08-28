import Controller from "@ember/controller";

export default class MarketplaceListingController extends Controller {
  queryParams = ["transaction_id"];

  transaction_id = null;
}
