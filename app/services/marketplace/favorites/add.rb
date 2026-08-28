# frozen_string_literal: true

module Marketplace
  class Favorites::Add
    include Service::Base

    params do
      attribute :listing_id, :integer

      validates :listing_id, presence: true
    end

    model :listing
    policy :visible
    step :add_favorite

    private

    def fetch_listing(params:)
      Marketplace::Listing.find_by(id: params.listing_id)
    end

    def visible(guardian:, listing:)
      guardian.can_see_marketplace_listing?(listing)
    end

    def add_favorite(guardian:, listing:)
      Marketplace::Favorite.create_or_find_by!(user_id: guardian.user.id, listing_id: listing.id)
    end
  end
end
