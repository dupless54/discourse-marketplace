# frozen_string_literal: true

class ScopeMarketplaceTransactionUniquenessToPending < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  OLD_INDEX = "idx_marketplace_transactions_listing_buyer_open"
  NEW_INDEX = "idx_marketplace_transactions_listing_buyer_pending"
  COLLECTION_INDEX = "idx_marketplace_transactions_listing_status_created"

  def up
    # The existing, stricter index guarantees that the new pending-only
    # unique index can be built without conflicting production rows. Build
    # the replacement first so there is never a window without the pending
    # invariant, then remove the old index. Concurrent DDL avoids holding a
    # long blocking table lock while the site remains online.
    add_index :marketplace_transactions,
              %i[listing_id buyer_id],
              unique: true,
              where: "status = 0",
              name: NEW_INDEX,
              algorithm: :concurrently

    # Supports the new participant-scoped collection query and its stable
    # pending-first, newest-first pagination. This is a demonstrated query
    # path, not a speculative index.
    add_index :marketplace_transactions,
              %i[listing_id status created_at id],
              order: {
                created_at: :desc,
                id: :desc,
              },
              name: COLLECTION_INDEX,
              algorithm: :concurrently

    remove_index :marketplace_transactions,
                 name: OLD_INDEX,
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    # Rollback is safe only while no buyer has multiple non-cancelled rows
    # for one listing. PostgreSQL will reject this add non-destructively if
    # newer completed history makes the old invariant impossible.
    add_index :marketplace_transactions,
              %i[listing_id buyer_id],
              unique: true,
              where: "status <> 20",
              name: OLD_INDEX,
              algorithm: :concurrently

    remove_index :marketplace_transactions,
                 name: COLLECTION_INDEX,
                 algorithm: :concurrently,
                 if_exists: true

    remove_index :marketplace_transactions,
                 name: NEW_INDEX,
                 algorithm: :concurrently,
                 if_exists: true
  end
end
