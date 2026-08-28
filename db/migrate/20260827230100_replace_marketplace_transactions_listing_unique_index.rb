# frozen_string_literal: true

class ReplaceMarketplaceTransactionsListingUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    # The old index allowed at most one open (non-cancelled) transaction per
    # listing, period -- the DB-level expression of "one listing = one sale".
    # Finite/unlimited listings need multiple different buyers to hold
    # concurrent open transactions on the same listing, so the constraint is
    # re-scoped to (listing_id, buyer_id): a single buyer still cannot open a
    # second pending transaction on a listing they already have one on, but
    # distinct buyers no longer block each other here -- capacity itself is
    # enforced separately by the stock_reserved/stock_sold CAS under the
    # listing's row lock (see Marketplace::Transactions::Create).
    #
    # Backward-safe: every existing row satisfied the old, strictly tighter
    # "at most one open transaction per listing_id" constraint, which
    # trivially satisfies this new per-(listing_id, buyer_id) constraint too.
    remove_index :marketplace_transactions, name: "idx_marketplace_transactions_listing_open"

    add_index :marketplace_transactions,
              %i[listing_id buyer_id],
              unique: true,
              where: "status <> 20",
              name: "idx_marketplace_transactions_listing_buyer_open"
  end
end
