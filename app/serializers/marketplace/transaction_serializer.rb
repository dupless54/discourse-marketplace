# frozen_string_literal: true

module Marketplace
  class TransactionSerializer < ApplicationSerializer
    attributes :id,
               :listing_id,
               :listing_title,
               :buyer_id,
               :seller_id,
               :status,
               :buyer_confirmed_at,
               :seller_confirmed_at,
               :completed_at,
               :cancelled_at,
               :cancelled_by_id,
               :created_at,
               :updated_at,
               :listing_title_snapshot,
               :price_cents_snapshot,
               :currency_snapshot,
               :snapshot_captured

    has_one :buyer, serializer: BasicUserSerializer, embed: :objects
    has_one :seller, serializer: BasicUserSerializer, embed: :objects

    # Collection callers preload :listing; singular mutation/show callers
    # naturally perform one association read at most.
    def listing_title
      object.listing.title
    end

    # A row created before the snapshot columns existed has no reliable
    # historical record (see Marketplace::Transaction#capture_transaction_
    # snapshot and docs/MARKETPLACE_ARCHITECTURE.md §2) -- falling back to
    # the listing's current values here is a display convenience only,
    # never persisted, and always flagged via snapshot_captured so a caller
    # never mistakes it for a verified historical price/title.
    def listing_title_snapshot
      object.listing_title_snapshot || object.listing.title
    end

    def price_cents_snapshot
      object.price_cents_snapshot || object.listing.price_cents
    end

    def currency_snapshot
      object.currency_snapshot || object.listing.currency
    end

    def snapshot_captured
      object.price_cents_snapshot.present?
    end
  end
end
