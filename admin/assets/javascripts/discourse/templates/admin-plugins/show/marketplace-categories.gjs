import MarketplaceCategoryAdmin from "discourse/plugins/discourse-marketplace/admin/components/marketplace-category-admin";

export default <template>
  <MarketplaceCategoryAdmin
    @initialCategories={{@controller.model.categories}}
  />
</template>
