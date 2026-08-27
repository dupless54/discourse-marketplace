import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class MarketplaceCategoriesRoute extends DiscourseRoute {
  model() {
    if (!this.currentUser?.admin) {
      return { categories: [] };
    }

    return ajax("/marketplace/admin/categories");
  }
}
