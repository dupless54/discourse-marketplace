import MarketplaceListingForm from "../../../components/marketplace-listing-form";

export default <template>
  <div class="marketplace-listing-edit">
    <MarketplaceListingForm
      @categories={{@controller.model.categories}}
      @listing={{@controller.model.listing}}
    />
  </div>
</template>
