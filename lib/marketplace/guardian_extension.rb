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

    def can_create_marketplace_transaction?(listing)
      return false if listing.blank?
      return false if !authenticated?
      return false if is_silenced?
      return false if current_user.suspended?
      return false if !listing.purchasable?
      return false if !listing.category&.enabled?
      return false if current_user.id == listing.seller_id

      true
    end

    def can_see_marketplace_transaction?(transaction)
      return false if transaction.blank?
      return true if is_staff?
      return false if !authenticated?

      current_user.id == transaction.buyer_id || current_user.id == transaction.seller_id
    end

    def can_confirm_marketplace_transaction?(transaction)
      return false if transaction.blank?
      return false if !authenticated?
      return false if is_silenced?
      return false if current_user.suspended?

      current_user.id == transaction.buyer_id || current_user.id == transaction.seller_id
    end

    def can_cancel_marketplace_transaction?(transaction)
      return false if transaction.blank?
      return true if is_staff?
      return false if !authenticated?
      return false if is_silenced?
      return false if current_user.suspended?

      current_user.id == transaction.buyer_id || current_user.id == transaction.seller_id
    end

    def can_create_marketplace_offer?(listing)
      can_create_marketplace_transaction?(listing) && listing.price_cents.to_i > 1
    end

    def can_see_marketplace_offer?(offer)
      return false if offer.blank?
      return true if is_staff?
      return false if !authenticated?

      offer.participant?(current_user.id)
    end

    def can_respond_marketplace_offer?(offer)
      return false if offer.blank?
      return false if !authenticated?
      return false if is_silenced?
      return false if current_user.suspended?
      return false if !offer.pending? || offer.effectively_expired?

      offer.recipient?(current_user.id)
    end

    def can_withdraw_marketplace_offer?(offer)
      return false if offer.blank?
      return false if !authenticated?
      return false if is_silenced?
      return false if current_user.suspended?
      return false if !offer.pending? || offer.effectively_expired?

      offer.proposer?(current_user.id)
    end
  end
end
