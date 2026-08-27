# frozen_string_literal: true

describe Marketplace::Notifier do
  fab!(:seller) { Fabricate(:user) }
  fab!(:buyer) { Fabricate(:user) }
  fab!(:staff) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:marketplace_category) }
  fab!(:listing) do
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[:reserved],
    )
  end

  def build_transaction(status: :pending, **overrides)
    Fabricate(
      :marketplace_transaction,
      listing: listing,
      buyer: buyer,
      seller: seller,
      status: Marketplace::Transaction.statuses[status],
      **overrides,
    )
  end

  def custom_notifications_for(user)
    Notification.where(user_id: user.id, notification_type: Notification.types[:custom])
  end

  describe ".notify_transaction_created" do
    it "notifies the seller only, with the buyer as the acting username" do
      transaction = build_transaction

      described_class.notify_transaction_created(transaction.id)

      expect(custom_notifications_for(seller).count).to eq(1)
      expect(custom_notifications_for(buyer).count).to eq(0)

      data = JSON.parse(custom_notifications_for(seller).first.data)
      expect(data["message"]).to eq("marketplace.notifications.transaction_started")
      expect(data["display_username"]).to eq(buyer.username)
      expect(data["topic_title"]).to eq(listing.title)
      expect(data["listing_id"]).to eq(listing.id)
      expect(data["title"]).to eq("marketplace.notifications.transaction_started_title")
    end

    it "does nothing for an unknown transaction id" do
      expect { described_class.notify_transaction_created(-1) }.not_to change { Notification.count }
    end
  end

  describe ".notify_transaction_first_confirmed" do
    it "notifies the seller when the buyer confirmed first" do
      transaction = build_transaction(buyer_confirmed_at: Time.current)

      described_class.notify_transaction_first_confirmed(transaction.id)

      expect(custom_notifications_for(seller).count).to eq(1)
      expect(custom_notifications_for(buyer).count).to eq(0)

      data = JSON.parse(custom_notifications_for(seller).first.data)
      expect(data["message"]).to eq("marketplace.notifications.transaction_confirmed")
      expect(data["listing_id"]).to eq(listing.id)
    end

    it "notifies the buyer when the seller confirmed first" do
      transaction = build_transaction(seller_confirmed_at: Time.current)

      described_class.notify_transaction_first_confirmed(transaction.id)

      expect(custom_notifications_for(buyer).count).to eq(1)
      expect(custom_notifications_for(seller).count).to eq(0)
    end

    it "notifies nobody when both sides are already confirmed" do
      transaction =
        build_transaction(
          status: :completed,
          buyer_confirmed_at: Time.current,
          seller_confirmed_at: Time.current,
          completed_at: Time.current,
        )

      expect {
        described_class.notify_transaction_first_confirmed(transaction.id)
      }.not_to change { Notification.count }
    end
  end

  describe ".notify_transaction_completed" do
    it "notifies both participants" do
      transaction =
        build_transaction(
          status: :completed,
          buyer_confirmed_at: Time.current,
          seller_confirmed_at: Time.current,
          completed_at: Time.current,
        )

      described_class.notify_transaction_completed(transaction.id)

      expect(custom_notifications_for(seller).count).to eq(1)
      expect(custom_notifications_for(buyer).count).to eq(1)

      data = JSON.parse(custom_notifications_for(buyer).first.data)
      expect(data["message"]).to eq("marketplace.notifications.transaction_completed")
      expect(data["listing_id"]).to eq(listing.id)
    end
  end

  describe ".notify_transaction_cancelled" do
    it "notifies only the seller when the buyer cancelled" do
      transaction =
        build_transaction(status: :cancelled, cancelled_at: Time.current, cancelled_by_id: buyer.id)

      described_class.notify_transaction_cancelled(transaction.id)

      expect(custom_notifications_for(seller).count).to eq(1)
      expect(custom_notifications_for(buyer).count).to eq(0)

      data = JSON.parse(custom_notifications_for(seller).first.data)
      expect(data["message"]).to eq("marketplace.notifications.transaction_cancelled")
      expect(data["listing_id"]).to eq(listing.id)
    end

    it "notifies only the buyer when the seller cancelled" do
      transaction =
        build_transaction(status: :cancelled, cancelled_at: Time.current, cancelled_by_id: seller.id)

      described_class.notify_transaction_cancelled(transaction.id)

      expect(custom_notifications_for(buyer).count).to eq(1)
      expect(custom_notifications_for(seller).count).to eq(0)
    end

    it "notifies both participants on a staff cancellation" do
      transaction =
        build_transaction(status: :cancelled, cancelled_at: Time.current, cancelled_by_id: staff.id)

      described_class.notify_transaction_cancelled(transaction.id)

      expect(custom_notifications_for(buyer).count).to eq(1)
      expect(custom_notifications_for(seller).count).to eq(1)
    end
  end
end
