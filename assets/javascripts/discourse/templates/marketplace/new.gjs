import MarketplaceListingForm from "../../components/marketplace-listing-form";

export default <template>
  <div class="marketplace-new">
    <MarketplaceListingForm @categories={{@controller.model.categories}} />
  </div>
</template>
