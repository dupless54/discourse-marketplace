import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class MarketplaceFavoriteButton extends Component {
  @service currentUser;

  @tracked favorited = !!this.args.listing.favorited;
  @tracked busy = false;
  @tracked errorMessage = null;

  get label() {
    return i18n(
      this.favorited
        ? "marketplace.favorites.remove"
        : "marketplace.favorites.add"
    );
  }

  @action
  async toggle() {
    if (this.busy) {
      return;
    }

    this.busy = true;
    this.errorMessage = null;
    try {
      const result = await ajax(
        `/marketplace/listings/${this.args.listing.id}/favorite`,
        { type: this.favorited ? "DELETE" : "POST" }
      );
      this.favorited = !!result.favorited;
      this.args.listing.favorited = this.favorited;
      this.args.onChange?.(this.args.listing.id, this.favorited);
    } catch (_error) {
      this.errorMessage = i18n("marketplace.favorites.error");
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{#if this.currentUser}}
      <div class="marketplace-favorite-control">
        <DButton
          class="btn-default marketplace-favorite-control__button"
          @translatedLabel={{this.label}}
          @icon="heart"
          @action={{this.toggle}}
          @disabled={{this.busy}}
          @isLoading={{this.busy}}
          @ariaPressed={{this.favorited}}
        />
        {{#if this.errorMessage}}
          <div class="marketplace-favorite-control__error" role="alert">
            {{this.errorMessage}}
          </div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
