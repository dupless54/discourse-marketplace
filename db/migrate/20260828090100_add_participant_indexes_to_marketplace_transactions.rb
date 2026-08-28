# frozen_string_literal: true

# Supports the new participant-scoped "mine" transaction collection (buyer
# and seller history views), the first query path that filters
# marketplace_transactions by buyer_id/seller_id directly rather than by
# listing_id. Without these, that query would fall back to a full table
# scan. Built concurrently to avoid a blocking table lock while the site
# remains online, matching the established convention for indexes on this
# table (see 20260828080000_scope_marketplace_transaction_uniqueness_to_pending.rb).
class AddParticipantIndexesToMarketplaceTransactions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BUYER_INDEX = "idx_marketplace_transactions_buyer_status_created"
  SELLER_INDEX = "idx_marketplace_transactions_seller_status_created"

  def up
    add_index :marketplace_transactions,
              %i[buyer_id status created_at id],
              order: {
                created_at: :desc,
                id: :desc,
              },
              name: BUYER_INDEX,
              algorithm: :concurrently

    add_index :marketplace_transactions,
              %i[seller_id status created_at id],
              order: {
                created_at: :desc,
                id: :desc,
              },
              name: SELLER_INDEX,
              algorithm: :concurrently
  end

  def down
    remove_index :marketplace_transactions,
                 name: BUYER_INDEX,
                 algorithm: :concurrently,
                 if_exists: true

    remove_index :marketplace_transactions,
                 name: SELLER_INDEX,
                 algorithm: :concurrently,
                 if_exists: true
  end
end
