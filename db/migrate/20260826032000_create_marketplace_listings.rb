# frozen_string_literal: true

class CreateMarketplaceListings < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_listings do |t|
      t.integer :seller_id, null: false
      t.string :title, limit: 255, null: false
      t.text :raw, null: false
      t.text :cooked, null: false
      t.bigint :category_id, null: false
      t.bigint :price_cents, null: false
      t.string :currency, limit: 3, null: false
      t.integer :status, null: false, default: 0
      t.datetime :published_at
      t.datetime :closed_at

      t.timestamps
    end

    add_index :marketplace_listings, %i[status category_id created_at]
    add_index :marketplace_listings, %i[seller_id status created_at]

    execute <<~SQL
      ALTER TABLE marketplace_listings
      ADD CONSTRAINT marketplace_listings_price_cents_check CHECK (price_cents >= 0)
    SQL

    execute <<~SQL
      ALTER TABLE marketplace_listings
      ADD CONSTRAINT marketplace_listings_title_length_check
      CHECK (char_length(title) BETWEEN 3 AND 255)
    SQL

    add_foreign_key :marketplace_listings,
                     :marketplace_categories,
                     column: :category_id,
                     on_delete: :restrict
  end
end
