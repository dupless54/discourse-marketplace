# frozen_string_literal: true

module Marketplace
  class Offers::Counter
    include Service::Base

    params do
      attribute :offer_id, :integer
      attribute :amount_cents, :integer

      validates :offer_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
      validates :amount_cents,
                presence: true,
                numericality: { only_integer: true, greater_than: 0 }
    end

    model :offer

    transaction do
      step :lock_offer
      step :ensure_actionable
      policy :can_respond_marketplace_offer
      step :validate_amount
      step :apply_counter
      step :record_counter_event
      step :register_countered_event
    end

    private

    def fetch_offer(params:)
      Marketplace::Offer.find_by(id: params.offer_id)
    end

    def lock_offer(offer:)
      offer.lock!
    end

    def ensure_actionable(offer:)
      if Marketplace::Offers::Helpers.expire_if_needed!(offer)
        context.fail!(offer_expired: true)
      end
      context.fail!(offer_not_pending: true) if !offer.pending?
    end

    def can_respond_marketplace_offer(guardian:, offer:)
      guardian.can_respond_marketplace_offer?(offer)
    end

    def validate_amount(params:, offer:)
      context.fail!(offer_amount_unchanged: true) if params.amount_cents == offer.amount_cents
      context.fail!(offer_above_asking_price: true) if params.amount_cents > offer.listing.price_cents
    end

    def apply_counter(params:, guardian:, offer:)
      offer.update!(
        amount_cents: params.amount_cents,
        proposed_by_id: guardian.user.id,
        responded_at: nil,
        responded_by_id: nil,
        expires_at: Marketplace::Offers::Helpers.expiry_time,
      )
    end

    def record_counter_event(offer:, guardian:)
      Marketplace::Offers::Helpers.record_event!(
        offer: offer,
        actor: guardian.user,
        event_type: :countered,
        amount_cents: offer.amount_cents,
      )
    end

    def register_countered_event(offer:)
      offer_id = offer.id
      DB.after_commit do
        DiscourseEvent.trigger(:marketplace_offer_countered, offer_id, continue_on_error: true)
      end
    end
  end
end
