# frozen_string_literal: true

class CreateMarketplaceCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_categories do |t|
      t.string :name, limit: 100, null: false
      t.string :slug, limit: 100, null: false
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :marketplace_categories, :slug, unique: true
    add_index :marketplace_categories, %i[enabled position]
  end
end
