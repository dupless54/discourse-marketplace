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
               :updated_at

    has_one :seller, serializer: BasicUserSerializer, embed: :objects
  end
end
