# frozen_string_literal: true

module Marketplace
  class Transaction < ActiveRecord::Base
    self.table_name = "marketplace_transactions"

    belongs_to :listing, class_name: "Marketplace::Listing"
    belongs_to :buyer, class_name: "User"
    belongs_to :seller, class_name: "User"
    belongs_to :cancelled_by, class_name: "User", optional: true

    enum :status, { pending: 0, completed: 10, cancelled: 20 }, scopes: false

    validates :listing, presence: true
    validates :buyer, presence: true
    validates :seller, presence: true
    validate :buyer_and_seller_must_differ

    before_validation :capture_transaction_snapshot, on: :create

    private

    def buyer_and_seller_must_differ
      return if buyer_id.blank? || seller_id.blank?
      return if buyer_id != seller_id

      errors.add(:buyer_id, "must be different from the seller")
    end

    # Captures the listing's commercial terms at the moment a NEW
    # transaction is created, unconditionally overwriting whatever the
    # in-memory attributes currently hold -- there is no code path (client
    # param, mass assignment, or otherwise) that can make this reflect
    # anything other than the associated listing's state right now. Only
    # runs on creation: a retried pending transaction and a confirm/cancel
    # save both persist an already-created row, so this callback never
    # touches it again, keeping the snapshot immutable for the lifetime of
    # the transaction. See docs/MARKETPLACE_ARCHITECTURE.md §2 for the
    # nullable-legacy-row rationale (no backfill, no invented history).
    def capture_transaction_snapshot
      return if listing.blank?

      self.listing_title_snapshot = listing.title
      self.price_cents_snapshot = listing.price_cents
      self.currency_snapshot = listing.currency
    end
  end
end

# == Schema Information
#
# Table name: marketplace_transactions
#
#  id                        :bigint           not null, primary key
#  buyer_confirmed_at        :datetime
#  cancelled_at              :datetime
#  completed_at              :datetime
#  currency_snapshot         :string(3)
#  listing_title_snapshot    :string(255)
#  price_cents_snapshot      :bigint
#  seller_confirmed_at       :datetime
#  status                    :integer          default("pending"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  buyer_id                  :integer          not null
#  cancelled_by_id           :integer
#  listing_id                :bigint           not null
#  seller_id                 :integer          not null
#
# Indexes
#
#  idx_marketplace_transactions_buyer_status_created    (buyer_id,status,created_at DESC,id DESC)
#  idx_marketplace_transactions_listing_buyer_pending   (listing_id,buyer_id) UNIQUE WHERE (status = 0)
#  idx_marketplace_transactions_listing_status_created  (listing_id,status,created_at DESC,id DESC)
#  idx_marketplace_transactions_seller_status_created   (seller_id,status,created_at DESC,id DESC)
#
# Foreign Keys
#
#  fk_rails_...  (listing_id => marketplace_listings.id) ON DELETE => restrict
#
