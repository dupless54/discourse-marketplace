# frozen_string_literal: true

module Marketplace
  class TransactionSerializer < ApplicationSerializer
    attributes :id,
               :listing_id,
               :buyer_id,
               :seller_id,
               :status,
               :buyer_confirmed_at,
               :seller_confirmed_at,
               :completed_at,
               :cancelled_at,
               :cancelled_by_id,
               :created_at,
               :updated_at
  end
end
