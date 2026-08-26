# frozen_string_literal: true

module Marketplace
  class ListingBrowseSerializer < ApplicationSerializer
    attributes :id, :title, :category_id, :price_cents, :currency, :status, :published_at

    has_one :seller, serializer: BasicUserSerializer, embed: :objects
  end
end
