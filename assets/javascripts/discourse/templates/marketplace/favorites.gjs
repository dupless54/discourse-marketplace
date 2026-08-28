import MarketplaceFavorites from "../../components/marketplace-favorites";

export default <template>
  <MarketplaceFavorites
    @initialListingsResult={{@controller.model.listingsResult}}
  />
</template>
