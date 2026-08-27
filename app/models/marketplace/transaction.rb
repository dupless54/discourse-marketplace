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

# == Schema Information
#
# Table name: marketplace_transactions
#
#  id                  :bigint           not null, primary key
#  buyer_confirmed_at  :datetime
#  cancelled_at        :datetime
#  completed_at        :datetime
#  seller_confirmed_at :datetime
#  status              :integer          default("pending"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  buyer_id            :integer          not null
#  cancelled_by_id     :integer
#  listing_id          :bigint           not null
#  seller_id           :integer          not null
#
# Indexes
#
#  idx_marketplace_transactions_listing_open  (listing_id) UNIQUE WHERE (status <> 20)
#
# Foreign Keys
#
#  fk_rails_...  (listing_id => marketplace_listings.id) ON DELETE => restrict
#
