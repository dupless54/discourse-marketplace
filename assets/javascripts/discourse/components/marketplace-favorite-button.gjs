import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import dIcon from "discourse/ui-kit/helpers/d-icon";
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
        <button
          type="button"
          class="btn btn-default marketplace-favorite-control__button"
          aria-pressed={{this.favorited}}
          disabled={{this.busy}}
          {{on "click" this.toggle}}
        >
          {{dIcon "heart"}}
          {{this.label}}
        </button>
        {{#if this.errorMessage}}
          <span class="marketplace-favorite-control__error">{{this.errorMessage}}</span>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
