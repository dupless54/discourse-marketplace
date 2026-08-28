# frozen_string_literal: true

module Marketplace
  module Offers
    module Helpers
      module_function

      def expiry_time(now = Time.current)
        now + SiteSetting.marketplace_offer_expiry_hours.to_i.hours
      end

      def expire_if_needed!(offer, now: Time.current)
        return false if !offer.effectively_expired?(now)

        offer.update!(
          status: Marketplace::Offer.statuses[:expired],
          responded_at: now,
          responded_by_id: nil,
        )
        Marketplace::OfferEvent.create!(
          offer: offer,
          actor: nil,
          event_type: Marketplace::OfferEvent.event_types[:expired],
        )
        true
      end

      def record_event!(offer:, actor:, event_type:, amount_cents: nil)
        Marketplace::OfferEvent.create!(
          offer: offer,
          actor: actor,
          event_type: Marketplace::OfferEvent.event_types.fetch(event_type.to_s),
          amount_cents: amount_cents,
          currency: amount_cents.present? ? offer.currency : nil,
        )
      end

      def pending_transaction_for(listing_id:, buyer_id:)
        Marketplace::Transaction.find_by(
          listing_id: listing_id,
          buyer_id: buyer_id,
          status: Marketplace::Transaction.statuses[:pending],
        )
      end

      # Must be called while the listing row is locked and from inside the
      # caller's DB transaction. It mirrors the existing direct-purchase CAS
      # semantics without changing Transactions::Create's public parameter
      # contract: SINGLE reserves its one slot, FINITE increments one reserved
      # unit, and UNLIMITED needs no persisted capacity reservation.
      def reserve_one!(listing, now: Time.current)
        if listing.single?
          affected_rows =
            Marketplace::Listing
              .where(id: listing.id, status: Marketplace::Listing.statuses[:active])
              .where("expires_at IS NULL OR expires_at > ?", now)
              .update_all(status: Marketplace::Listing.statuses[:reserved], updated_at: now)

          raise Marketplace::TransactionInvariantViolation if affected_rows != 1
        elsif listing.finite?
          affected_rows =
            Marketplace::Listing
              .where(id: listing.id, status: Marketplace::Listing.statuses[:active])
              .where("expires_at IS NULL OR expires_at > ?", now)
              .where("stock_reserved + stock_sold < stock_quantity")
              .update_all(["stock_reserved = stock_reserved + 1, updated_at = ?", now])

          raise Marketplace::TransactionInvariantViolation if affected_rows != 1
        end
      end
    end
  end
end
