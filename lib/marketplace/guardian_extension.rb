# frozen_string_literal: true

module Marketplace
  module GuardianExtension
    def can_create_marketplace_listing?
      return false if !authenticated?
      return false if is_silenced?
      return false if current_user.suspended?

      current_user.has_trust_level?(SiteSetting.marketplace_min_trust_level.to_i)
    end

    def can_see_marketplace_listing?(listing)
      return false if listing.blank?
      return true if is_staff?
      return true if authenticated? && listing.seller_id == current_user.id
      return false if listing.draft?

      listing.category&.enabled?
    end

    def can_edit_marketplace_listing?(listing)
      return false if listing.blank?
      return true if is_staff?
      return false if !authenticated?
      return false if is_silenced?
      return false if current_user.suspended?
      return false if listing.seller_id != current_user.id

      listing.draft? || listing.active?
    end

    def can_transition_marketplace_listing_status?(listing)
      return false if listing.blank?
      return true if is_staff?
      return false if !authenticated?
      return false if is_silenced?
      return false if current_user.suspended?

      listing.seller_id == current_user.id
    end
  end
end
