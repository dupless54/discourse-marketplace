import MarketplaceListingDetail from "../../../components/marketplace-listing-detail";

export default <template>
  <MarketplaceListingDetail
    @listing={{@controller.model.listing}}
    @transactions={{@controller.model.transactions}}
    @transactionsPagination={{@controller.model.transactionsPagination}}
    @selectedTransactionId={{@controller.model.selectedTransactionId}}
  />
</template>
