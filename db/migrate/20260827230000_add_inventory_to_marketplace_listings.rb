# frozen_string_literal: true

class AddInventoryToMarketplaceListings < ActiveRecord::Migration[8.0]
  def change
    # Default 0 (single) maps every existing row to the pre-existing
    # one-listing-one-sale behavior with no backfill needed -- see
    # docs/MARKETPLACE_ARCHITECTURE.md for the inventory design.
    add_column :marketplace_listings, :inventory_mode, :integer, null: false, default: 0
    add_column :marketplace_listings, :stock_quantity, :bigint
    add_column :marketplace_listings, :stock_reserved, :bigint, null: false, default: 0
    add_column :marketplace_listings, :stock_sold, :bigint, null: false, default: 0
    add_column :marketplace_listings, :expires_at, :datetime

    execute <<~SQL
      ALTER TABLE marketplace_listings
      ADD CONSTRAINT marketplace_listings_inventory_mode_check
      CHECK (inventory_mode IN (0, 10, 20))
    SQL

    # Finite listings must carry a positive capacity with reserved+sold never
    # exceeding it; single/unlimited listings never use stock_quantity or
    # stock_reserved at all (unlimited may still use stock_sold as a
    # non-gating sales counter).
    execute <<~SQL
      ALTER TABLE marketplace_listings
      ADD CONSTRAINT marketplace_listings_stock_shape_check
      CHECK (
        (
          inventory_mode = 10
          AND stock_quantity IS NOT NULL
          AND stock_quantity >= 1
          AND stock_reserved >= 0
          AND stock_sold >= 0
          AND stock_reserved + stock_sold <= stock_quantity
        )
        OR
        (
          inventory_mode <> 10
          AND stock_quantity IS NULL
          AND stock_reserved = 0
          AND stock_sold >= 0
        )
      )
    SQL
  end
end
