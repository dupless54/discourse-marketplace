# frozen_string_literal: true

module Marketplace
  class Offers::Accept
    include Service::Base

    params do
      attribute :offer_id, :integer

      validates :offer_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
    end

    model :offer
    model :listing

    transaction do
      # Keep the same lock order as offer creation and direct purchase:
      # listing first, then the offer row. This prevents a listing/offer
      # lock inversion when a buyer retries while the recipient responds.
      step :lock_listing
      step :lock_offer
      step :prepare_accept

      only_if(:not_replay) do
        policy :can_respond_marketplace_offer
        step :validate_buyer_and_listing
        step :validate_current_terms
        step :reject_existing_pending_transaction
        model :transaction_candidate, :build_transaction
        step :save_transaction
        step :reserve_listing
        step :mark_offer_accepted
        step :record_accepted_event
        step :register_accepted_event
        step :publish_transaction
      end
    end

    private

    def fetch_offer(params:)
      Marketplace::Offer.includes(:accepted_transaction).find_by(id: params.offer_id)
    end

    def fetch_listing(offer:)
      offer&.listing
    end

    def lock_listing(listing:)
      listing.lock!
    end

    def lock_offer(offer:)
      offer.lock!
    end

    def prepare_accept(offer:, guardian:)
      if offer.accepted? &&
           offer.responded_by_id == guardian.user.id &&
           offer.accepted_transaction.present?
        context[:transaction] = offer.accepted_transaction
        context[:replay] = true
        return
      end

      context.fail!(offer_expired: true) if offer.effectively_expired?
      context.fail!(offer_not_pending: true) if !offer.pending?
      context[:replay] = false
    end

    def not_replay(replay:)
      !replay
    end

    def can_respond_marketplace_offer(guardian:, offer:)
      guardian.can_respond_marketplace_offer?(offer)
    end

    def validate_buyer_and_listing(offer:, listing:)
      buyer_guardian = Guardian.new(offer.buyer)
      context.fail!(listing_unavailable: true) if !buyer_guardian.can_create_marketplace_transaction?(listing)
    end

    def validate_current_terms(offer:, listing:)
      context.fail!(offer_currency_changed: true) if offer.currency != listing.currency
      context.fail!(offer_above_asking_price: true) if offer.amount_cents > listing.price_cents
    end

    def reject_existing_pending_transaction(offer:, listing:)
      existing =
        Marketplace::Offers::Helpers.pending_transaction_for(
          listing_id: listing.id,
          buyer_id: offer.buyer_id,
        )
      context.fail!(buyer_has_pending_transaction: true) if existing.present?
    end

    def build_transaction(offer:, listing:)
      Marketplace::Transaction.new(
        listing: listing,
        buyer: offer.buyer,
        seller: offer.seller,
        status: Marketplace::Transaction.statuses[:pending],
        marketplace_agreed_price_cents: offer.amount_cents,
      )
    end

    def save_transaction(transaction_candidate:)
      transaction_candidate.save!
    rescue ActiveRecord::RecordNotUnique
      context.fail!(buyer_has_pending_transaction: true)
    end

    def reserve_listing(listing:)
      Marketplace::Offers::Helpers.reserve_one!(listing)
    end

    def mark_offer_accepted(offer:, guardian:, transaction_candidate:)
      now = Time.current
      offer.update!(
        status: Marketplace::Offer.statuses[:accepted],
        responded_at: now,
        responded_by_id: guardian.user.id,
        accepted_transaction: transaction_candidate,
      )
    end

    def record_accepted_event(offer:, guardian:)
      Marketplace::Offers::Helpers.record_event!(
        offer: offer,
        actor: guardian.user,
        event_type: :accepted,
        amount_cents: offer.amount_cents,
      )
    end

    def register_accepted_event(offer:)
      offer_id = offer.id
      DB.after_commit do
        DiscourseEvent.trigger(:marketplace_offer_accepted, offer_id, continue_on_error: true)
      end
    end

    def publish_transaction(transaction_candidate:)
      context[:transaction] = transaction_candidate
    end
  end
end
