import MarketplaceMyListings from "../../components/marketplace-my-listings";

export default <template>
  <MarketplaceMyListings
    @initialListingsResult={{@controller.model.listingsResult}}
  />
</template>
