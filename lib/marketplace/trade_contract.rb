# frozen_string_literal: true

module Marketplace
  module TradeContract
    VERSION = 1

    TransactionInfo =
      Data.define(:transaction_id, :listing_id, :buyer_id, :seller_id, :completed_at) do
        def initialize(transaction_id:, buyer_id:, seller_id:, completed_at:, listing_id: nil)
          super(transaction_id:, listing_id:, buyer_id:, seller_id:, completed_at:)
        end
      end

    # Only a completed transaction is ever eligible for trade feedback (see
    # docs/MARKETPLACE_ARCHITECTURE.md §7), so this is the only lookup this
    # contract exposes: unknown, pending, and cancelled all collapse to the
    # same nil result rather than a generic transaction_info/find API that
    # would let a caller re-derive eligibility incorrectly.
    def self.completed_transaction_info(transaction_id)
      id = normalize_id(transaction_id)
      return nil if id.nil?

      transaction =
        Marketplace::Transaction.select(
          :id,
          :listing_id,
          :buyer_id,
          :seller_id,
          :completed_at,
        ).find_by(id: id, status: Marketplace::Transaction.statuses[:completed])
      return nil if transaction.blank?

      TransactionInfo.new(
        transaction_id: transaction.id,
        listing_id: transaction.listing_id,
        buyer_id: transaction.buyer_id,
        seller_id: transaction.seller_id,
        completed_at: transaction.completed_at,
      )
    end

    def self.normalize_id(value)
      return nil unless value.is_a?(Integer)

      value.positive? ? value : nil
    end
    private_class_method :normalize_id
  end
end
