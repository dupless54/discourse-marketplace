# frozen_string_literal: true

module Marketplace
  class OfferSerializer < ApplicationSerializer
    attributes :id,
               :listing_id,
               :listing_title,
               :listing_status,
               :asking_price_cents,
               :buyer_id,
               :seller_id,
               :proposed_by_id,
               :responded_by_id,
               :status,
               :amount_cents,
               :currency,
               :expires_at,
               :responded_at,
               :accepted_transaction_id,
               :created_at,
               :updated_at

    has_one :buyer, serializer: BasicUserSerializer, embed: :objects
    has_one :seller, serializer: BasicUserSerializer, embed: :objects

    def listing_title
      object.listing.title
    end

    def listing_status
      object.listing.status
    end

    def asking_price_cents
      object.listing.price_cents
    end

    # A pending row whose deadline passed is exposed as expired immediately,
    # even before another mutation needs to persist the terminal state. This
    # keeps GET endpoints side-effect free while every write path still calls
    # Helpers.expire_if_needed! before allowing an action.
    def status
      object.effective_status
    end
  end
end
