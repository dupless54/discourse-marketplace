# frozen_string_literal: true

module Marketplace
  class Offers::Withdraw
    include Service::Base

    params do
      attribute :offer_id, :integer

      validates :offer_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
    end

    model :offer

    transaction do
      step :lock_offer
      step :prepare_withdraw

      only_if(:not_replay) do
        policy :can_withdraw_marketplace_offer
        step :withdraw_offer
        step :record_withdrawn_event
        step :register_withdrawn_event
      end
    end

    private

    def fetch_offer(params:)
      Marketplace::Offer.find_by(id: params.offer_id)
    end

    def lock_offer(offer:)
      offer.lock!
    end

    def prepare_withdraw(offer:, guardian:)
      if offer.withdrawn? && offer.responded_by_id == guardian.user.id
        context[:replay] = true
        return
      end

      if Marketplace::Offers::Helpers.expire_if_needed!(offer)
        context.fail!(offer_expired: true)
      end
      context.fail!(offer_not_pending: true) if !offer.pending?
      context[:replay] = false
    end

    def not_replay(replay:)
      !replay
    end

    def can_withdraw_marketplace_offer(guardian:, offer:)
      guardian.can_withdraw_marketplace_offer?(offer)
    end

    def withdraw_offer(offer:, guardian:)
      offer.update!(
        status: Marketplace::Offer.statuses[:withdrawn],
        responded_at: Time.current,
        responded_by_id: guardian.user.id,
      )
    end

    def record_withdrawn_event(offer:, guardian:)
      Marketplace::Offers::Helpers.record_event!(
        offer: offer,
        actor: guardian.user,
        event_type: :withdrawn,
      )
    end

    def register_withdrawn_event(offer:)
      offer_id = offer.id
      DB.after_commit do
        DiscourseEvent.trigger(:marketplace_offer_withdrawn, offer_id, continue_on_error: true)
      end
    end
  end
end
