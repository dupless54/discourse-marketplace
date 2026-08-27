# frozen_string_literal: true

module Marketplace
  # Listens for Marketplace's own transaction lifecycle events and creates
  # in-forum notifications for the affected participant(s). Uses
  # Notification.types[:custom] with topic_id/post_number left nil -- the
  # verified, supported mechanism for a plugin that has no topic/post of its
  # own to notify against (see plugins/discourse-solved in discourse/discourse
  # core for the precedent this mirrors: Notification.create! with
  # notification_type: :custom and a data.message/topic_title/display_username
  # payload; topic_id/post_number are nullable columns on notifications).
  #
  # Each public method here is only ever invoked from a DiscourseEvent
  # listener registered with continue_on_error: true (see plugin.rb), so a
  # raise here is logged and swallowed by core rather than propagating into
  # the triggering request -- matching the same best-effort posture already
  # documented for :marketplace_transaction_completed in
  # docs/MARKETPLACE_ARCHITECTURE.md §7.
  module Notifier
    def self.notify_transaction_created(transaction_id)
      transaction = find_transaction(transaction_id)
      return if transaction.blank?

      notify(
        recipient_id: transaction.seller_id,
        actor: transaction.buyer,
        listing: transaction.listing,
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
        # Both or neither confirmed by the time this fired (e.g. the second
        # confirmation already landed) -- nothing single-sided left to notify.
        return
      end

      notify(
        recipient_id: recipient_id,
        actor: actor,
        listing: transaction.listing,
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
          # Staff cancellation: neither participant acted, so notify both.
          [transaction.buyer, transaction.seller]
        end

      actor = transaction.cancelled_by

      recipients.each do |recipient|
        notify(
          recipient_id: recipient.id,
          actor: actor,
          listing: transaction.listing,
          message: "marketplace.notifications.transaction_cancelled",
        )
      end
    end

    def self.find_transaction(transaction_id)
      Marketplace::Transaction.find_by(id: transaction_id)
    end
    private_class_method :find_transaction

    # listing_id travels in the payload so the client can link the
    # notification straight back to /marketplace/listings/:id (see the
    # "custom" notification type renderer registered in
    # assets/javascripts/discourse/initializers/marketplace-notifications.js).
    # The recipient is always a transaction participant already, so this
    # adds no exposure beyond what they can already reach.
    def self.notify(recipient_id:, actor:, listing:, message:)
      Notification.create!(
        notification_type: Notification.types[:custom],
        user_id: recipient_id,
        data: {
          message: message,
          display_username: actor&.username,
          topic_title: listing.title,
          listing_id: listing.id,
          title: "#{message}_title",
        }.to_json,
      )
    end
    private_class_method :notify
  end
end
