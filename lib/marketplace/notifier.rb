# frozen_string_literal: true

module Marketplace
  # Creates best-effort in-forum notifications for Marketplace transaction
  # and offer lifecycle events. Marketplace owns no topic/post, so these use
  # Notification.types[:custom] with a plugin-specific message prefix. Every
  # caller is registered through a DiscourseEvent listener with
  # continue_on_error: true; notification delivery can never roll back a
  # committed commerce transition.
  module Notifier
    def self.notify_transaction_created(transaction_id)
      transaction = find_transaction(transaction_id)
      return if transaction.blank?

      notify(
        recipient_id: transaction.seller_id,
        actor: transaction.buyer,
        listing: transaction.listing,
        transaction_id: transaction.id,
        message: "marketplace.notifications.transaction_started",
      )
    end

    def self.notify_transaction_first_confirmed(transaction_id)
      transaction = find_transaction(transaction_id)
      return if transaction.blank?

      if transaction.buyer_confirmed_at.present? && transaction.seller_confirmed_at.blank?
        recipient_id = transaction.seller_id
        actor = transaction.buyer
      elsif transaction.seller_confirmed_at.present? && transaction.buyer_confirmed_at.blank?
        recipient_id = transaction.buyer_id
        actor = transaction.seller
      else
        return
      end

      notify(
        recipient_id: recipient_id,
        actor: actor,
        listing: transaction.listing,
        transaction_id: transaction.id,
        message: "marketplace.notifications.transaction_confirmed",
      )
    end

    def self.notify_transaction_completed(transaction_id)
      transaction = find_transaction(transaction_id)
      return if transaction.blank?

      [transaction.buyer, transaction.seller].each do |recipient|
        notify(
          recipient_id: recipient.id,
          actor: nil,
          listing: transaction.listing,
          transaction_id: transaction.id,
          message: "marketplace.notifications.transaction_completed",
        )
      end
    end

    def self.notify_transaction_cancelled(transaction_id)
      transaction = find_transaction(transaction_id)
      return if transaction.blank?

      canceller_id = transaction.cancelled_by_id
      recipients =
        if canceller_id == transaction.buyer_id
          [transaction.seller]
        elsif canceller_id == transaction.seller_id
          [transaction.buyer]
        else
          [transaction.buyer, transaction.seller]
        end

      actor = transaction.cancelled_by

      recipients.each do |recipient|
        notify(
          recipient_id: recipient.id,
          actor: actor,
          listing: transaction.listing,
          transaction_id: transaction.id,
          message: "marketplace.notifications.transaction_cancelled",
        )
      end
    end

    def self.notify_offer_created(offer_id)
      offer = find_offer(offer_id)
      return if offer.blank?

      notify_offer_counterpart(offer, "marketplace.notifications.offer_received")
    end

    def self.notify_offer_countered(offer_id)
      offer = find_offer(offer_id)
      return if offer.blank?

      notify_offer_counterpart(offer, "marketplace.notifications.offer_countered")
    end

    def self.notify_offer_accepted(offer_id)
      offer = find_offer(offer_id)
      return if offer.blank?

      notify_offer_responder_counterpart(offer, "marketplace.notifications.offer_accepted")
    end

    def self.notify_offer_rejected(offer_id)
      offer = find_offer(offer_id)
      return if offer.blank?

      notify_offer_responder_counterpart(offer, "marketplace.notifications.offer_rejected")
    end

    def self.notify_offer_withdrawn(offer_id)
      offer = find_offer(offer_id)
      return if offer.blank?

      notify_offer_responder_counterpart(offer, "marketplace.notifications.offer_withdrawn")
    end

    def self.find_transaction(transaction_id)
      Marketplace::Transaction.find_by(id: transaction_id)
    end
    private_class_method :find_transaction

    def self.find_offer(offer_id)
      Marketplace::Offer.includes(:buyer, :seller, :listing, :responded_by).find_by(id: offer_id)
    end
    private_class_method :find_offer

    # After create/counter, proposed_by is the actor and recipient_id is the
    # user now expected to respond.
    def self.notify_offer_counterpart(offer, message)
      actor = offer.proposed_by
      notify(
        recipient_id: offer.recipient_id,
        actor: actor,
        listing: offer.listing,
        offer_id: offer.id,
        message: message,
      )
    end
    private_class_method :notify_offer_counterpart

    # Terminal responses record responded_by_id, so notify only the other
    # participant. This avoids self-notifications for accept/reject/withdraw.
    def self.notify_offer_responder_counterpart(offer, message)
      actor = offer.responded_by
      return if actor.blank?

      recipient_id = actor.id == offer.buyer_id ? offer.seller_id : offer.buyer_id
      notify(
        recipient_id: recipient_id,
        actor: actor,
        listing: offer.listing,
        offer_id: offer.id,
        message: message,
      )
    end
    private_class_method :notify_offer_responder_counterpart

    def self.notify(
      recipient_id:,
      actor:,
      listing:,
      message:,
      transaction_id: nil,
      offer_id: nil
    )
      Notification.create!(
        notification_type: Notification.types[:custom],
        user_id: recipient_id,
        data: {
          message: message,
          display_username: actor&.username,
          topic_title: listing.title,
          listing_id: listing.id,
          transaction_id: transaction_id,
          offer_id: offer_id,
          title: "#{message}_title",
        }.compact.to_json,
      )
    end
    private_class_method :notify
  end
end
