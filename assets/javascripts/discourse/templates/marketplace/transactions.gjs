import MarketplaceTransactionCenter from "../../components/marketplace-transaction-center";

export default <template>
  <MarketplaceTransactionCenter
    @initialRole={{@controller.model.initialRole}}
    @initialResult={{@controller.model.initialResult}}
  />
</template>
