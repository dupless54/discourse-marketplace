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

    # Collection callers preload :listing; singular mutation/show callers
    # naturally perform one association read at most.
    def listing_title
      object.listing.title
    end
  end
end
