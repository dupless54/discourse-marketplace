# frozen_string_literal: true

module Marketplace
  class Transactions::Create
    include Service::Base

    params do
      attribute :listing_id, :integer

      validates :listing_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
    end

    model :listing

    transaction do
      step :lock_listing
      model :existing_transaction, :fetch_existing_pending_transaction, optional: true
      step :reject_if_contended

      only_if(:existing_pending_for_current_buyer) do
        step :verify_replay_invariant
        step :assign_existing_transaction_as_result
      end

      only_if(:no_existing_pending_transaction) do
        policy :can_create_marketplace_transaction
        model :transaction_candidate, :build_transaction
        step :save_transaction
        step :reserve_listing
        step :register_created_event
        step :publish_transaction_result
      end
    end

    private

    def fetch_listing(params:)
      Marketplace::Listing.find_by(id: params.listing_id)
    end

    def lock_listing(listing:)
      listing.lock!
    end

    # SINGLE has exactly one slot, so "the" pending transaction (any buyer)
    # is both the contention signal and the replay candidate -- unchanged
    # from the original one-listing-one-sale design.
    #
    # FINITE/UNLIMITED allow many buyers to hold concurrent pending
    # transactions on the same listing, so only *this* buyer's own pending
    # transaction is a replay candidate; a different buyer's pending
    # transaction is normal, expected concurrency, not contention.
    def fetch_existing_pending_transaction(listing:, guardian:)
      if listing.single?
        Marketplace::Transaction.find_by(
          listing_id: listing.id,
          status: Marketplace::Transaction.statuses[:pending],
        )
      else
        return nil if !guardian.authenticated?

        Marketplace::Transaction.find_by(
          listing_id: listing.id,
          buyer_id: guardian.user.id,
          status: Marketplace::Transaction.statuses[:pending],
        )
      end
    end

    # A different buyer already holding the listing's one slot is a normal,
    # expected contention outcome for SINGLE (not a bug) and must produce
    # the same stable `listing_unavailable` marker as the RecordNotUnique DB
    # backstop below, so the eventual controller can render one generic
    # response for both.
    #
    # For FINITE, the analogous race is the last unit selling out between
    # page load and click; genuine ineligibility (draft/archived/expired/
    # self-trade/silenced/etc.) is left to the ordinary policy check below
    # so it keeps returning a plain policy failure, not this marker.
    # UNLIMITED has no capacity to contend over, so this never fires for it.
    def reject_if_contended(existing_transaction:, guardian:, listing:)
      if listing.single?
        return if existing_transaction.blank?
        return if guardian.authenticated? && existing_transaction.buyer_id == guardian.user.id

        context.fail!(listing_unavailable: true)
      elsif listing.finite?
        return if existing_transaction.present?
        return if !listing.active? || listing.expired?

        context.fail!(listing_unavailable: true) if listing.stock_available.to_i <= 0
      end
    end

    def existing_pending_for_current_buyer(existing_transaction:)
      existing_transaction.present?
    end

    def no_existing_pending_transaction(existing_transaction:)
      existing_transaction.blank?
    end

    def verify_replay_invariant(listing:)
      if listing.single?
        raise Marketplace::TransactionInvariantViolation if !listing.reserved?
      elsif listing.finite?
        raise Marketplace::TransactionInvariantViolation if listing.stock_reserved < 1
      end
    end

    def assign_existing_transaction_as_result(existing_transaction:)
      context[:transaction] = existing_transaction
    end

    def can_create_marketplace_transaction(guardian:, listing:)
      guardian.can_create_marketplace_transaction?(listing)
    end

    def build_transaction(guardian:, listing:)
      Marketplace::Transaction.new(
        listing: listing,
        buyer: guardian.user,
        seller: listing.seller,
        status: Marketplace::Transaction.statuses[:pending],
      )
    end

    # The partial unique index on marketplace_transactions(listing_id,
    # buyer_id) is the DB backstop behind the row lock. If it ever fires (a
    # concurrent insert slipped past the lock somehow), we must not keep
    # using a Postgres transaction that is now in an aborted state: catch
    # only the specific exception, immediately fail the context (which
    # raises and unwinds the enclosing transaction do...end, rolling
    # everything back), and expose the same generic marker as the
    # different-buyer contention path.
    #
    # The candidate lives under :transaction_candidate, not the public
    # :transaction result key, until reservation has also succeeded (see
    # #publish_transaction_result) -- context assignments are not rolled
    # back by a failed/raised step, only the DB is, so exposing the
    # candidate under :transaction any earlier would leak an unsaved or
    # since-rolled-back object as the service's public result.
    def save_transaction(transaction_candidate:)
      transaction_candidate.save!
    rescue ActiveRecord::RecordNotUnique
      context.fail!(listing_unavailable: true)
    end

    def reserve_listing(listing:)
      if listing.single?
        reserve_single_capacity(listing)
      elsif listing.finite?
        reserve_finite_capacity(listing)
      end
      # unlimited: no capacity to reserve, nothing to persist.
    end

    def reserve_single_capacity(listing)
      now = Time.current
      affected_rows =
        Marketplace::Listing
          .where(id: listing.id, status: Marketplace::Listing.statuses[:active])
          .where("expires_at IS NULL OR expires_at > ?", now)
          .update_all(status: Marketplace::Listing.statuses[:reserved], updated_at: now)

      raise Marketplace::TransactionInvariantViolation if affected_rows != 1
    end

    def reserve_finite_capacity(listing)
      now = Time.current
      affected_rows =
        Marketplace::Listing
          .where(id: listing.id, status: Marketplace::Listing.statuses[:active])
          .where("expires_at IS NULL OR expires_at > ?", now)
          .where("stock_reserved + stock_sold < stock_quantity")
          .update_all(["stock_reserved = stock_reserved + 1, updated_at = ?", now])

      raise Marketplace::TransactionInvariantViolation if affected_rows != 1
    end

    # Registered only once the save and the reservation CAS have both
    # succeeded, mirroring the completion event's placement in Confirm (see
    # docs/MARKETPLACE_ARCHITECTURE.md §7/§8): DB.after_commit ties the
    # notification to this transaction's real, committed outcome, and
    # continue_on_error: true keeps a failing listener from turning an
    # already-successful create into a failed result.
    def register_created_event(transaction_candidate:)
      transaction_id = transaction_candidate.id
      DB.after_commit do
        DiscourseEvent.trigger(
          :marketplace_transaction_created,
          transaction_id,
          continue_on_error: true,
        )
      end
    end

    # Only reached once both the save and the reservation CAS have
    # succeeded -- this is the single point where the newly created
    # transaction becomes the service's public result.
    def publish_transaction_result(transaction_candidate:)
      context[:transaction] = transaction_candidate
    end
  end
end
