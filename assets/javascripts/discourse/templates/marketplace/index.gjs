import MarketplaceBrowse from "../../components/marketplace-browse";

export default <template>
  <MarketplaceBrowse
    @categories={{@controller.model.categories}}
    @initialListingsResult={{@controller.model.listingsResult}}
  />
</template>
