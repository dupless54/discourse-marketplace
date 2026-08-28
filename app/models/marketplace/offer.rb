# frozen_string_literal: true

module Marketplace
  class Offer < ActiveRecord::Base
    self.table_name = "marketplace_offers"

    belongs_to :listing, class_name: "Marketplace::Listing"
    belongs_to :buyer, class_name: "User"
    belongs_to :seller, class_name: "User"
    belongs_to :proposed_by, class_name: "User"
    belongs_to :responded_by, class_name: "User", optional: true
    belongs_to :accepted_transaction,
               class_name: "Marketplace::Transaction",
               optional: true

    has_many :events,
             class_name: "Marketplace::OfferEvent",
             dependent: :destroy,
             inverse_of: :offer

    enum :status,
         { pending: 0, accepted: 10, rejected: 20, withdrawn: 30, expired: 40 },
         scopes: false

    validates :listing, :buyer, :seller, :proposed_by, presence: true
    validates :amount_cents,
              numericality: {
                only_integer: true,
                greater_than: 0,
                less_than_or_equal_to: 9_223_372_036_854_775_807,
              }
    validates :currency, presence: true, length: { is: 3 }
    validates :expires_at, presence: true

    validate :participants_match_listing
    validate :proposer_is_participant
    validate :responder_is_participant
    validate :accepted_transaction_matches_offer

    def effectively_expired?(now = Time.current)
      pending? && expires_at.present? && expires_at <= now
    end

    def effective_status(now = Time.current)
      effectively_expired?(now) ? "expired" : status
    end

    def recipient_id
      proposed_by_id == buyer_id ? seller_id : buyer_id
    end

    def participant?(user_id)
      user_id.present? && (user_id == buyer_id || user_id == seller_id)
    end

    def recipient?(user_id)
      pending? && recipient_id == user_id
    end

    def proposer?(user_id)
      pending? && proposed_by_id == user_id
    end

    private

    def participants_match_listing
      return if listing.blank?

      errors.add(:seller_id, "must match the listing seller") if seller_id != listing.seller_id
      errors.add(:buyer_id, "must be different from the seller") if buyer_id == listing.seller_id
      errors.add(:currency, "must match the listing currency") if currency != listing.currency
    end

    def proposer_is_participant
      return if proposed_by_id.blank? || buyer_id.blank? || seller_id.blank?
      return if proposed_by_id == buyer_id || proposed_by_id == seller_id

      errors.add(:proposed_by_id, "must be an offer participant")
    end

    def responder_is_participant
      return if responded_by_id.blank? || buyer_id.blank? || seller_id.blank?
      return if responded_by_id == buyer_id || responded_by_id == seller_id

      errors.add(:responded_by_id, "must be an offer participant")
    end

    def accepted_transaction_matches_offer
      return if accepted_transaction.blank?

      if accepted_transaction.listing_id != listing_id ||
           accepted_transaction.buyer_id != buyer_id ||
           accepted_transaction.seller_id != seller_id
        errors.add(:accepted_transaction_id, "must match the offer participants and listing")
      end
    end
  end
end

# == Schema Information
#
# Table name: marketplace_offers
#
#  id                      :bigint           not null, primary key
#  amount_cents            :bigint           not null
#  currency                :string(3)        not null
#  expires_at              :datetime         not null
#  responded_at            :datetime
#  status                  :integer          default("pending"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  accepted_transaction_id :bigint
#  buyer_id                :integer          not null
#  listing_id              :bigint           not null
#  proposed_by_id          :integer          not null
#  responded_by_id         :integer
#  seller_id               :integer          not null
#
# Indexes
#
#  idx_marketplace_offers_accepted_transaction    (accepted_transaction_id) UNIQUE WHERE (accepted_transaction_id IS NOT NULL)
#  idx_marketplace_offers_buyer_status_updated    (buyer_id,status,updated_at DESC,id DESC)
#  idx_marketplace_offers_listing_buyer_pending   (listing_id,buyer_id) UNIQUE WHERE (status = 0)
#  idx_marketplace_offers_listing_status_updated  (listing_id,status,updated_at DESC,id DESC)
#  idx_marketplace_offers_seller_status_updated   (seller_id,status,updated_at DESC,id DESC)
#
# Foreign Keys
#
#  fk_rails_...  (accepted_transaction_id => marketplace_transactions.id) ON DELETE => restrict
#  fk_rails_...  (listing_id => marketplace_listings.id) ON DELETE => restrict
#
