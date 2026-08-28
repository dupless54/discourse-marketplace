# frozen_string_literal: true

module Marketplace
  class ListingSerializer < ApplicationSerializer
    attributes :id,
               :title,
               :category_id,
               :price_cents,
               :currency,
               :status,
               :published_at,
               :closed_at,
               :created_at,
               :updated_at,
               :inventory_mode,
               :stock_quantity,
               :stock_available,
               :stock_sold,
               :expires_at,
               :expired,
               :purchasable

    has_one :seller, serializer: BasicUserSerializer, embed: :objects

    def expired
      object.expired?
    end

    def purchasable
      object.purchasable?
    end
  end
end
