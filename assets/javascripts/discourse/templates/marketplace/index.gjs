import { i18n } from "discourse-i18n";
import MarketplaceBrowse from "../../components/marketplace-browse";

export default <template>
  {{#if @controller.model.initialLoadFailed}}
    <div class="wrap">
      <div class="alert alert-error marketplace-initial-load-error" role="status">
        {{i18n "marketplace.browse.initial_load_error"}}
      </div>
    </div>
  {{/if}}

  <MarketplaceBrowse
    @categories={{@controller.model.categories}}
    @initialListingsResult={{@controller.model.listingsResult}}
  />
</template>
