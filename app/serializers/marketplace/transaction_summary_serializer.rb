# frozen_string_literal: true

module Marketplace
  # Transaction Center card/row shape: everything TransactionSerializer
  # already exposes (id, snapshot terms, timestamps, confirmation state,
  # buyer/seller) plus the two fields that only make sense for a
  # viewer-scoped collection -- which side of the trade the current viewer
  # is on, and a thumbnail for the listing without the client needing a
  # second request. Only ever built from Marketplace::TransactionsController
  # #mine, whose query already restricts every row to
  # buyer_id/seller_id == current_user.id, so `role` here is never
  # ambiguous.
  class TransactionSummarySerializer < Marketplace::TransactionSerializer
    attributes :role, :listing_thumbnail_url

    def role
      object.buyer_id == scope.user.id ? "buyer" : "seller"
    end

    def listing_thumbnail_url
      object.listing.thumbnail_url
    end
  end
end
