# frozen_string_literal: true

class CreateMarketplaceTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_transactions do |t|
      t.bigint :listing_id, null: false
      t.integer :buyer_id, null: false
      t.integer :seller_id, null: false
      t.integer :status, null: false, default: 0
      t.datetime :buyer_confirmed_at
      t.datetime :seller_confirmed_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.integer :cancelled_by_id

      t.timestamps
    end

    add_foreign_key :marketplace_transactions,
                     :marketplace_listings,
                     column: :listing_id,
                     on_delete: :restrict

    add_index :marketplace_transactions,
              :listing_id,
              unique: true,
              where: "status <> 20",
              name: "idx_marketplace_transactions_listing_open"

    add_check_constraint :marketplace_transactions,
                          "status IN (0, 10, 20)",
                          name: "marketplace_transactions_status_check"

    add_check_constraint :marketplace_transactions,
                          "buyer_id <> seller_id",
                          name: "marketplace_transactions_buyer_seller_check"

    add_check_constraint :marketplace_transactions,
                          <<~SQL.squish,
                            (
                              (
                                status = 0
                                AND completed_at IS NULL
                                AND cancelled_at IS NULL
                                AND cancelled_by_id IS NULL
                                AND NOT (
                                  buyer_confirmed_at IS NOT NULL
                                  AND seller_confirmed_at IS NOT NULL
                                )
                              )
                              OR
                              (
                                status = 10
                                AND completed_at IS NOT NULL
                                AND buyer_confirmed_at IS NOT NULL
                                AND seller_confirmed_at IS NOT NULL
                                AND cancelled_at IS NULL
                                AND cancelled_by_id IS NULL
                              )
                              OR
                              (
                                status = 20
                                AND cancelled_at IS NOT NULL
                                AND cancelled_by_id IS NOT NULL
                                AND completed_at IS NULL
                                AND NOT (
                                  buyer_confirmed_at IS NOT NULL
                                  AND seller_confirmed_at IS NOT NULL
                                )
                              )
                            )
                          SQL
                          name: "marketplace_transactions_status_shape_check"
  end
end
