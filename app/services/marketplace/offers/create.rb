# frozen_string_literal: true

module Marketplace
  class Offers::Create
    include Service::Base

    params do
      attribute :listing_id, :integer
      attribute :amount_cents, :integer

      validates :listing_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
      validates :amount_cents, presence: true, numericality: { only_integer: true, greater_than: 0 }
    end

    model :listing

    transaction do
      step :lock_listing
      policy :can_create_marketplace_offer
      step :prepare_offer_slot
      step :validate_amount
      model :offer, :build_offer
      step :save_offer
      step :record_proposed_event
      step :register_created_event
    end

    private

    def fetch_listing(params:)
      Marketplace::Listing.find_by(id: params.listing_id)
    end

    def lock_listing(listing:)
      listing.lock!
    end

    def can_create_marketplace_offer(guardian:, listing:)
      guardian.can_create_marketplace_offer?(listing)
    end

    def prepare_offer_slot(guardian:, listing:)
      existing =
        Marketplace::Offer.lock.find_by(
          listing_id: listing.id,
          buyer_id: guardian.user.id,
          status: Marketplace::Offer.statuses[:pending],
        )

      if existing.present?
        Marketplace::Offers::Helpers.expire_if_needed!(existing)
        context.fail!(offer_already_pending: true) if existing.pending?
      end

      if Marketplace::Offers::Helpers.pending_transaction_for(
           listing_id: listing.id,
           buyer_id: guardian.user.id,
         ).present?
        context.fail!(buyer_has_pending_transaction: true)
      end
    end

    def validate_amount(params:, listing:)
      if params.amount_cents >= listing.price_cents
        context.fail!(offer_not_below_asking_price: true)
      end
    end

    def build_offer(params:, guardian:, listing:)
      Marketplace::Offer.new(
        listing: listing,
        buyer: guardian.user,
        seller: listing.seller,
        proposed_by: guardian.user,
        amount_cents: params.amount_cents,
        currency: listing.currency,
        status: Marketplace::Offer.statuses[:pending],
        expires_at: Marketplace::Offers::Helpers.expiry_time,
      )
    end

    def save_offer(offer:)
      offer.save!
    rescue ActiveRecord::RecordNotUnique
      context.fail!(offer_already_pending: true)
    end

    def record_proposed_event(offer:, guardian:)
      Marketplace::Offers::Helpers.record_event!(
        offer: offer,
        actor: guardian.user,
        event_type: :proposed,
        amount_cents: offer.amount_cents,
      )
    end

    def register_created_event(offer:)
      offer_id = offer.id
      DB.after_commit do
        DiscourseEvent.trigger(:marketplace_offer_created, offer_id, continue_on_error: true)
      end
    end
  end
end
