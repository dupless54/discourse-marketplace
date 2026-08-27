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
      step :reject_if_contended_by_another_buyer

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

    def fetch_existing_pending_transaction(listing:)
      Marketplace::Transaction.find_by(
        listing_id: listing.id,
        status: Marketplace::Transaction.statuses[:pending],
      )
    end

    # A different buyer already holding the listing is a normal, expected
    # contention outcome (not a bug) and must produce the same stable
    # `listing_unavailable` marker as the RecordNotUnique DB backstop below,
    # so the eventual controller can render one generic response for both.
    def reject_if_contended_by_another_buyer(existing_transaction:, guardian:)
      return if existing_transaction.blank?
      return if guardian.authenticated? &&
                existing_transaction.buyer_id == guardian.user.id

      context.fail!(listing_unavailable: true)
    end

    def existing_pending_for_current_buyer(existing_transaction:)
      existing_transaction.present?
    end

    def no_existing_pending_transaction(existing_transaction:)
      existing_transaction.blank?
    end

    def verify_replay_invariant(listing:)
      raise Marketplace::TransactionInvariantViolation if !listing.reserved?
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

    # The partial unique index on marketplace_transactions(listing_id) is the
    # DB backstop behind the row lock. If it ever fires (a concurrent insert
    # slipped past the lock somehow), we must not keep using a Postgres
    # transaction that is now in an aborted state: catch only the specific
    # exception, immediately fail the context (which raises and unwinds the
    # enclosing transaction do...end, rolling everything back), and expose
    # the same generic marker as the different-buyer contention path.
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
      now = Time.current
      affected_rows =
        Marketplace::Listing
          .where(id: listing.id, status: Marketplace::Listing.statuses[:active])
          .update_all(status: Marketplace::Listing.statuses[:reserved], updated_at: now)

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
