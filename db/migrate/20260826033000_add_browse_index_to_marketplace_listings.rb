# frozen_string_literal: true

class AddBrowseIndexToMarketplaceListings < ActiveRecord::Migration[8.0]
  def change
    add_index :marketplace_listings,
              %i[status published_at id],
              name: "idx_marketplace_listings_browse_status_published"
  end
end
