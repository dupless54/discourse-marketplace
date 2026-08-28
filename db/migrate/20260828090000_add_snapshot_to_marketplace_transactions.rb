# frozen_string_literal: true

# Persists the commercial terms of a listing at the moment a transaction is
# created (see Marketplace::Transaction#capture_transaction_snapshot). A
# seller may later edit a finite/unlimited listing's title/price/currency,
# and transaction history must keep showing what the buyer actually agreed
# to, not the listing's current (possibly since-edited) values.
#
# Nullable, no backfill: rows created before this migration have no
# reliable historical record of what the listing looked like at their own
# creation time (the listing may already have been edited since, possibly
# more than once, with no audit trail to reconstruct from) -- writing the
# listing's *current* values into these columns for old rows would present
# a guess as if it were captured history. Leaving them NULL is the honest
# backward-compatible choice; Marketplace::TransactionSerializer falls back
# to the listing's current values for legacy rows and exposes
# `snapshot_captured: false` so callers can tell the difference.
class AddSnapshotToMarketplaceTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :marketplace_transactions, :listing_title_snapshot, :string, limit: 255
    add_column :marketplace_transactions, :price_cents_snapshot, :bigint
    add_column :marketplace_transactions, :currency_snapshot, :string, limit: 3
  end
end
