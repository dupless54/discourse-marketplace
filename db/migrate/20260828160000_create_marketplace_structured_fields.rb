# frozen_string_literal: true

class CreateMarketplaceStructuredFields < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_category_field_definitions do |t|
      t.bigint :category_id, null: false
      t.string :key, limit: 50, null: false
      t.string :label, limit: 100, null: false
      t.string :field_type, limit: 20, null: false
      t.boolean :required, null: false, default: false
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0
      t.string :placeholder, limit: 150
      t.string :help_text, limit: 500
      t.jsonb :choices, null: false, default: []

      t.timestamps
    end

    add_index :marketplace_category_field_definitions,
              %i[category_id key],
              unique: true,
              name: "idx_marketplace_category_fields_unique_key"
    add_index :marketplace_category_field_definitions,
              %i[category_id position id],
              name: "idx_marketplace_category_fields_order"
    add_foreign_key :marketplace_category_field_definitions,
                    :marketplace_categories,
                    column: :category_id,
                    on_delete: :restrict

    add_check_constraint :marketplace_category_field_definitions,
                         "field_type IN ('text', 'textarea', 'integer', 'boolean', 'select')",
                         name: "marketplace_category_fields_type_check"
    add_check_constraint :marketplace_category_field_definitions,
                         "position >= 0",
                         name: "marketplace_category_fields_position_check"

    create_table :marketplace_listing_field_values do |t|
      t.bigint :listing_id, null: false
      t.bigint :field_definition_id, null: false
      t.text :value, null: false

      t.timestamps
    end

    add_index :marketplace_listing_field_values,
              %i[listing_id field_definition_id],
              unique: true,
              name: "idx_marketplace_listing_field_values_unique"
    add_index :marketplace_listing_field_values,
              :field_definition_id,
              name: "idx_marketplace_listing_field_values_definition"
    add_foreign_key :marketplace_listing_field_values,
                    :marketplace_listings,
                    column: :listing_id,
                    on_delete: :cascade
    add_foreign_key :marketplace_listing_field_values,
                    :marketplace_category_field_definitions,
                    column: :field_definition_id,
                    on_delete: :restrict
  end
end
