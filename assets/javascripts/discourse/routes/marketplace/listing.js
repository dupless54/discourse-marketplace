import Route from "@ember/routing/route";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class MarketplaceListingRoute extends Route {
  @service currentUser;

  async model(params) {
    const listingResult = await ajax(
      `/marketplace/listings/${params.listing_id}`
    );

    let transaction = null;
    if (this.currentUser) {
      try {
        const transactionResult = await ajax(
          `/marketplace/listings/${params.listing_id}/transaction`
        );
        transaction = transactionResult.transaction;
      } catch {
        // No open transaction exists yet for the current user on this listing --
        // that is the common case, not an error.
        transaction = null;
      }
    }

    return { listing: listingResult.listing, transaction };
  }
}
