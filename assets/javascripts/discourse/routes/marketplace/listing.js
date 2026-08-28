import Route from "@ember/routing/route";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class MarketplaceListingRoute extends Route {
  @service currentUser;

  queryParams = {
    transaction_id: { refreshModel: true },
  };

  async model(params) {
    const listingResult = await ajax(
      `/marketplace/listings/${params.listing_id}`
    );

    let transactions = [];
    let transactionsPagination = null;
    if (this.currentUser) {
      const baseUrl = `/marketplace/listings/${params.listing_id}/transactions`;

      if (params.transaction_id) {
        const exactResult = await ajax(
          `${baseUrl}?transaction_id=${encodeURIComponent(params.transaction_id)}`
        );
        transactions = exactResult.transactions;
        transactionsPagination = exactResult.pagination;

        const pageResult = await ajax(`${baseUrl}?page=1`);
        const ids = new Set(transactions.map((transaction) => transaction.id));
        transactions = [
          ...transactions,
          ...pageResult.transactions.filter(
            (transaction) => !ids.has(transaction.id)
          ),
        ];
        transactionsPagination = pageResult.pagination;
      } else {
        const result = await ajax(`${baseUrl}?page=1`);
        transactions = result.transactions;
        transactionsPagination = result.pagination;
      }
    }

    return {
      listing: listingResult.listing,
      transactions,
      transactionsPagination,
      selectedTransactionId: params.transaction_id
        ? Number(params.transaction_id)
        : null,
    };
  }
}
