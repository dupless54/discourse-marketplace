import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

const EMPTY_LISTINGS_RESULT = {
  listings: [],
  pagination: { page: 1, per_page: 20, has_more: false },
};

export default class MarketplaceIndexRoute extends Route {
  async model() {
    const [categoriesResult, listingsResult] = await Promise.allSettled([
      ajax("/marketplace/categories"),
      ajax("/marketplace/listings"),
    ]);

    const categories =
      categoriesResult.status === "fulfilled"
        ? (categoriesResult.value?.categories ?? [])
        : [];
    const resolvedListings =
      listingsResult.status === "fulfilled"
        ? listingsResult.value
        : EMPTY_LISTINGS_RESULT;

    return {
      categories,
      listingsResult: {
        ...EMPTY_LISTINGS_RESULT,
        ...resolvedListings,
        pagination: {
          ...EMPTY_LISTINGS_RESULT.pagination,
          ...(resolvedListings?.pagination ?? {}),
        },
        listings: resolvedListings?.listings ?? [],
      },
      initialLoadFailed:
        categoriesResult.status === "rejected" ||
        listingsResult.status === "rejected",
    };
  }
}
