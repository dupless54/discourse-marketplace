# frozen_string_literal: true

module Marketplace
  class OfferEvent < ActiveRecord::Base
    self.table_name = "marketplace_offer_events"

    belongs_to :offer, class_name: "Marketplace::Offer", inverse_of: :events
    belongs_to :actor, class_name: "User", optional: true

    enum :event_type,
         {
           proposed: 0,
           countered: 10,
           accepted: 20,
           rejected: 30,
           withdrawn: 40,
           expired: 50,
         },
         scopes: false

    validates :offer, :event_type, presence: true
    validates :amount_cents,
              numericality: { only_integer: true, greater_than: 0 },
              allow_nil: true
    validates :currency, length: { is: 3 }, allow_nil: true
    validate :actor_is_participant
    validate :human_events_require_actor

    private

    def actor_is_participant
      return if offer.blank? || actor_id.blank?
      return if offer.participant?(actor_id)

      errors.add(:actor_id, "must be an offer participant")
    end

    def human_events_require_actor
      return if expired?
      return if actor_id.present?

      errors.add(:actor_id, "is required for user-authored offer events")
    end
  end
end
