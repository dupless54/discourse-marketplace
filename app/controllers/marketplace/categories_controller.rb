# frozen_string_literal: true

module Marketplace
  class CategoriesController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME

    def index
      categories = Marketplace::Category.browsable

      render_json_dump(
        categories: serialize_data(categories, Marketplace::CategorySerializer),
      )
    end
  end
end
