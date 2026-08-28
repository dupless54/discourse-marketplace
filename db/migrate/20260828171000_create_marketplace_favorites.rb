# frozen_string_literal: true

class CreateMarketplaceFavorites < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_favorites do |t|
      t.integer :user_id, null: false
      t.bigint :listing_id, null: false

      t.timestamps
    end

    add_index :marketplace_favorites,
              %i[user_id listing_id],
              unique: true,
              name: "idx_marketplace_favorites_user_listing"

    add_index :marketplace_favorites,
              %i[user_id created_at id],
              name: "idx_marketplace_favorites_user_created"

    add_index :marketplace_favorites,
              :listing_id,
              name: "idx_marketplace_favorites_listing"

    add_foreign_key :marketplace_favorites,
                    :marketplace_listings,
                    column: :listing_id,
                    on_delete: :cascade
  end
end
