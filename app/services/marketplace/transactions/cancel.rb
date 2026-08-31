# frozen_string_literal: true

module Marketplace
  class Transactions::Cancel
    include Service::Base

    params do
      attribute :transaction_id, :integer

      validates :transaction_id,
                presence: true,
                numericality: {
                  only_integer: true,
                  greater_than: 0,
                }
    end

    model :transaction_record, :fetch_transaction

    transaction do
      step :lock_transaction
      step :lock_listing
      policy :can_cancel_marketplace_transaction

      # Already-cancelled is a pure replay: no listing state requirement, no
      # mutation. This is what makes replaying cancellation of an OLD
      # transaction safe even after a NEW pending transaction has since
      # reserved the same listing again -- this branch never reads or
      # writes `listing` at all.
      only_if(:transaction_cancelled) { step :publish_transaction_result }

      only_if(:transaction_completed) { step :reject_completed }

      only_if(:transaction_pending) do
        step :verify_pending_invariant
        step :cancel_transaction_and_release_listing
        step :publish_transaction_result
      end
    end

    private

    def fetch_transaction(params:)
      Marketplace::Transaction.find_by(id: params.transaction_id)
    end

    def lock_transaction(transaction_record:)
      transaction_record.lock!
    end

    def lock_listing(transaction_record:)
      listing = transaction_record.listing
      listing.lock!
      context[:listing] = listing
    end

    def can_cancel_marketplace_transaction(guardian:, transaction_record:)
      guardian.can_cancel_marketplace_transaction?(transaction_record)
    end

    def transaction_cancelled(transaction_record:)
      transaction_record.cancelled?
    end

    def transaction_completed(transaction_record:)
      transaction_record.completed?
    end

    def transaction_pending(transaction_record:)
      transaction_record.pending?
    end

    # Completed is terminal and cannot be cancelled, even by staff -- the
    # moderation override grants authorization to attempt the action, not
    # the power to reverse a finished trade.
    def reject_completed
      context.fail!(transaction_not_cancellable: true)
    end

    # Reached only after both locks and authorization have succeeded, for
    # every successful outcome (cancelled replay, pending cancellation).
    # This is the single place the public :transaction result key is ever
    # assigned.
    def publish_transaction_result(transaction_record:)
      context[:transaction] = transaction_record
    end

    def verify_pending_invariant(listing:)
      if listing.single?
        raise Marketplace::TransactionInvariantViolation if !listing.reserved?
      elsif listing.finite?
        raise Marketplace::TransactionInvariantViolation if listing.stock_reserved < 1
      end
    end

    # guardian.user is safe to dereference here: the
    # can_cancel_marketplace_transaction policy has already succeeded, and
    # that predicate only returns true for a real authenticated user
    # (either a participant or actual staff) -- never for anonymous.
    #
    # Confirmation timestamps are deliberately left untouched: a pending
    # transaction may already carry one participant's prior confirmation,
    # and that audit history must survive cancellation. completed_at also
    # stays nil, since it was already nil on a pending row. All three
    # cancellation fields are set in memory together, then persisted with
    # exactly one save! -- there is never an intermediate row with
    # status = cancelled but missing cancelled_at/cancelled_by_id.
    def cancel_transaction_and_release_listing(transaction_record:, listing:, guardian:)
      now = Time.current

      transaction_record.status = Marketplace::Transaction.statuses[:cancelled]
      transaction_record.cancelled_at = now
      transaction_record.cancelled_by_id = guardian.user.id
      transaction_record.save!

      release_listing_capacity(listing, now)

      transaction_id = transaction_record.id
      DB.after_commit do
        DiscourseEvent.trigger(
          :marketplace_transaction_cancelled,
          transaction_id,
          continue_on_error: true,
        )
      end
    end

    # SINGLE: the whole-listing reserved->active CAS, unchanged from before
    # inventory modes existed. FINITE: only the one reserved unit this
    # transaction held is released (stock_reserved -= 1) -- listing.status
    # is never touched, since finite purchasability is derived from the
    # counters rather than status (see Marketplace::Listing#purchasable?).
    # UNLIMITED: nothing was ever reserved, so there is nothing to release.
    def release_listing_capacity(listing, now)
      if listing.single?
        affected_rows =
          Marketplace::Listing.where(
            id: listing.id,
            status: Marketplace::Listing.statuses[:reserved],
          ).update_all(status: Marketplace::Listing.statuses[:active], updated_at: now)

        raise Marketplace::TransactionInvariantViolation if affected_rows != 1
      elsif listing.finite?
        affected_rows =
          Marketplace::Listing
            .where(id: listing.id, inventory_mode: Marketplace::Listing.inventory_modes[:finite])
            .where("stock_reserved > 0")
            .update_all(["stock_reserved = stock_reserved - 1, updated_at = ?", now])

        raise Marketplace::TransactionInvariantViolation if affected_rows != 1
      end
    end
  end
end
