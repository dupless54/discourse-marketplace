import MarketplaceFavoriteButton from "../../../components/marketplace-favorite-button";
import MarketplaceListingDetail from "../../../components/marketplace-listing-detail";
import MarketplaceOfferPanel from "../../../components/marketplace-offer-panel";

export default <template>
  <div class="marketplace-listing-favorite-bar">
    <MarketplaceFavoriteButton @listing={{@controller.model.listing}} />
  </div>
  <MarketplaceListingDetail
    @listing={{@controller.model.listing}}
    @transactions={{@controller.model.transactions}}
    @transactionsPagination={{@controller.model.transactionsPagination}}
    @selectedTransactionId={{@controller.model.selectedTransactionId}}
  />
  <MarketplaceOfferPanel
    @listing={{@controller.model.listing}}
    @hasPendingTransaction={{@controller.model.hasPendingTransaction}}
  />
</template>
