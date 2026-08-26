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

    private

    def buyer_and_seller_must_differ
      return if buyer_id.blank? || seller_id.blank?
      return if buyer_id != seller_id

      errors.add(:buyer_id, "must be different from the seller")
    end
  end
end
