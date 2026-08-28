import MarketplaceOfferCenter from "../../components/marketplace-offer-center";

export default <template>
  <MarketplaceOfferCenter
    @initialRole={{@controller.model.initialRole}}
    @initialResult={{@controller.model.initialResult}}
  />
</template>
