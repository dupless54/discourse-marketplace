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
               :updated_at

    has_one :buyer, serializer: BasicUserSerializer, embed: :objects
    has_one :seller, serializer: BasicUserSerializer, embed: :objects

    # Only ever serializes a single record per request (show/create/confirm/
    # cancel all return exactly one transaction), so this extra read is not
    # an N+1: it never runs per-row inside a collection.
    def listing_title
      object.listing.title
    end
  end
end
