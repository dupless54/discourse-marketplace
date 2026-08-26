# frozen_string_literal: true

module Marketplace
  class Transactions::Confirm
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
      policy :can_confirm_marketplace_transaction

      only_if(:transaction_cancelled) { step :reject_cancelled }

      only_if(:transaction_completed) { step :publish_transaction_result }

      only_if(:transaction_pending) do
        step :verify_pending_invariant
        step :determine_actor_and_confirmation_state

        only_if(:actor_already_confirmed) { step :publish_transaction_result }

        only_if(:actor_confirming_first_time_alone) do
          step :record_first_confirmation
          step :publish_transaction_result
        end

        only_if(:actor_confirming_second_and_final) do
          step :complete_transaction_and_listing
          step :publish_transaction_result
        end
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

    def can_confirm_marketplace_transaction(guardian:, transaction_record:)
      guardian.can_confirm_marketplace_transaction?(transaction_record)
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

    # Cancelled is terminal and unconfirmable. Named marker only -- no
    # transaction/listing detail is exposed, matching the same generic
    # posture as Create's listing_unavailable marker.
    def reject_cancelled
      context.fail!(transaction_not_confirmable: true)
    end

    # Reached only after both locks and authorization have succeeded, for
    # every successful outcome (pending replay, first confirm, final
    # confirm, completed replay). This is the single place the public
    # :transaction result key is ever assigned.
    def publish_transaction_result(transaction_record:)
      context[:transaction] = transaction_record
    end

    def verify_pending_invariant(listing:)
      raise Marketplace::TransactionInvariantViolation if !listing.reserved?
    end

    # guardian.user is safe to dereference here: the can_confirm_marketplace_transaction
    # policy has already succeeded by this point, which requires authentication.
    def determine_actor_and_confirmation_state(transaction_record:, guardian:)
      actor_is_buyer = guardian.user.id == transaction_record.buyer_id
      context[:actor_is_buyer] = actor_is_buyer

      actor_confirmed_at =
        actor_is_buyer ? transaction_record.buyer_confirmed_at : transaction_record.seller_confirmed_at
      other_confirmed_at =
        actor_is_buyer ? transaction_record.seller_confirmed_at : transaction_record.buyer_confirmed_at

      context[:actor_already_confirmed_at_start] = actor_confirmed_at.present?
      context[:other_already_confirmed] = other_confirmed_at.present?
    end

    def actor_already_confirmed(actor_already_confirmed_at_start:)
      actor_already_confirmed_at_start
    end

    def actor_confirming_first_time_alone(actor_already_confirmed_at_start:, other_already_confirmed:)
      !actor_already_confirmed_at_start && !other_already_confirmed
    end

    def actor_confirming_second_and_final(actor_already_confirmed_at_start:, other_already_confirmed:)
      !actor_already_confirmed_at_start && other_already_confirmed
    end

    # First confirmation: only the actor's own timestamp changes. Status
    # stays pending, completed_at stays nil, listing is untouched -- a
    # single save, never two.
    def record_first_confirmation(transaction_record:, actor_is_buyer:)
      now = Time.current

      if actor_is_buyer
        transaction_record.buyer_confirmed_at = now
      else
        transaction_record.seller_confirmed_at = now
      end

      transaction_record.save!
    end

    # Final confirmation. The Phase 1 status-shape CHECK requires a
    # completed row to have BOTH confirmation timestamps, completed_at, and
    # no cancellation fields all at once -- so the actor's timestamp,
    # status, and completed_at must be set together and persisted in one
    # single save!, never as an intermediate pending-with-both-timestamps
    # row. The listing CAS is a separate, subsequent persistence step, as
    # required.
    #
    # The completion event is registered here, last, only once the CAS has
    # proven exactly one row changed -- never earlier, so a subsequent
    # invariant-violation raise (which aborts the enclosing DB transaction)
    # has nothing to unwind: DB.after_commit ties the callback to that same
    # transaction's real outcome, firing once after it truly commits and
    # never if it rolls back (see docs/MARKETPLACE_ARCHITECTURE.md §11).
    # Only the scalar id is captured -- never transaction_record, listing,
    # or guardian -- and continue_on_error: true keeps a failing listener
    # from turning this already-committed completion into a failed result.
    def complete_transaction_and_listing(transaction_record:, listing:, actor_is_buyer:)
      now = Time.current

      if actor_is_buyer
        transaction_record.buyer_confirmed_at = now
      else
        transaction_record.seller_confirmed_at = now
      end
      transaction_record.status = Marketplace::Transaction.statuses[:completed]
      transaction_record.completed_at = now
      transaction_record.save!

      affected_rows =
        Marketplace::Listing
          .where(id: listing.id, status: Marketplace::Listing.statuses[:reserved])
          .update_all(status: Marketplace::Listing.statuses[:sold], closed_at: now, updated_at: now)

      raise Marketplace::TransactionInvariantViolation if affected_rows != 1

      transaction_id = transaction_record.id
      DB.after_commit do
        DiscourseEvent.trigger(
          :marketplace_transaction_completed,
          transaction_id,
          continue_on_error: true,
        )
      end
    end
  end
end
