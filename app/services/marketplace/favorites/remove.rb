# frozen_string_literal: true

module Marketplace
  class Favorites::Remove
    include Service::Base

    params do
      attribute :listing_id, :integer

      validates :listing_id, presence: true
    end

    step :remove_favorite

    private

    # Deliberately idempotent and non-enumerating: removing a favorite only
    # touches the authenticated user's own row and succeeds even when the
    # favorite (or listing) no longer exists.
    def remove_favorite(guardian:, params:)
      Marketplace::Favorite.where(user_id: guardian.user.id, listing_id: params.listing_id).delete_all
    end
  end
end
