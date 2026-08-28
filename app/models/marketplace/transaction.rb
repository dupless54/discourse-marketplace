# frozen_string_literal: true

module Marketplace
  class Transaction < ActiveRecord::Base
    self.table_name = "marketplace_transactions"

    # Offer acceptance is an internal transaction-creation path. The agreed
    # price never comes from TransactionsController params; Offers::Accept
    # sets this transient value immediately before save so the immutable
    # transaction snapshot reflects the negotiated amount instead of the
    # listing's public asking price.
    attr_accessor :marketplace_agreed_price_cents

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

    # Captures the commercial terms at the moment a NEW transaction is
    # created. Direct purchases snapshot the listing price. An accepted
    # Marketplace::Offer may supply a trusted, server-owned agreed price via
    # #marketplace_agreed_price_cents; no public transaction API accepts that
    # attribute. Only runs on creation, keeping the persisted snapshot
    # immutable for the lifetime of the transaction.
    def capture_transaction_snapshot
      return if listing.blank?

      self.listing_title_snapshot = listing.title
      self.price_cents_snapshot = marketplace_agreed_price_cents || listing.price_cents
      self.currency_snapshot = listing.currency
    end
  end
end

# == Schema Information
#
# Table name: marketplace_transactions
#
#  id                     :bigint           not null, primary key
#  buyer_confirmed_at     :datetime
#  cancelled_at           :datetime
#  completed_at           :datetime
#  currency_snapshot      :string(3)
#  listing_title_snapshot :string(255)
#  price_cents_snapshot   :bigint
#  seller_confirmed_at    :datetime
#  status                 :integer          default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  buyer_id               :integer          not null
#  cancelled_by_id        :integer
#  listing_id             :bigint           not null
#  seller_id              :integer          not null
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
