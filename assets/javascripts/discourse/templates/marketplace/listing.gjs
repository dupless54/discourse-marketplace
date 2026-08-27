import MarketplaceListingDetail from "../../components/marketplace-listing-detail";

export default <template>
  <MarketplaceListingDetail
    @listing={{@controller.model.listing}}
    @transaction={{@controller.model.transaction}}
  />
</template>
