# frozen_string_literal: true

describe Marketplace::TradeContract do
  fab!(:seller) { Fabricate(:user) }
  fab!(:buyer) { Fabricate(:user) }
  fab!(:category) { Fabricate(:marketplace_category) }
  fab!(:listing) do
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[:active],
    )
  end

  def build_pending
    Fabricate(:marketplace_transaction, listing: listing, buyer: buyer, seller: seller)
  end

  def build_completed
    transaction = build_pending
    now = Time.zone.now
    transaction.update_columns(
      status: Marketplace::Transaction.statuses[:completed],
      buyer_confirmed_at: now,
      seller_confirmed_at: now,
      completed_at: now,
    )
    transaction.reload
  end

  def build_cancelled
    transaction = build_pending
    transaction.update_columns(
      status: Marketplace::Transaction.statuses[:cancelled],
      cancelled_at: Time.zone.now,
      cancelled_by_id: seller.id,
    )
    transaction.reload
  end

  def nonexistent_id
    (Marketplace::Transaction.maximum(:id) || 0) + 1_000_000
  end

  describe ".completed_transaction_info" do
    describe "invalid or ineligible input" do
      it "returns nil for an unknown positive id" do
        expect(described_class.completed_transaction_info(nonexistent_id)).to be_nil
      end

      it "returns nil for nil" do
        expect(described_class.completed_transaction_info(nil)).to be_nil
      end

      it "returns nil for zero" do
        expect(described_class.completed_transaction_info(0)).to be_nil
      end

      it "returns nil for a negative integer" do
        expect(described_class.completed_transaction_info(-1)).to be_nil
      end

      it "returns nil for a non-integer string" do
        expect(described_class.completed_transaction_info("abc")).to be_nil
      end

      it "returns nil for a numeric string" do
        transaction = build_completed
        expect(described_class.completed_transaction_info(transaction.id.to_s)).to be_nil
      end

      it "returns nil for a pending transaction" do
        transaction = build_pending
        expect(described_class.completed_transaction_info(transaction.id)).to be_nil
      end

      it "returns nil for a cancelled transaction" do
        transaction = build_cancelled
        expect(described_class.completed_transaction_info(transaction.id)).to be_nil
      end

      it "does not raise for any invalid input" do
        [nil, 0, -1, "abc", 1.5, [], {}].each do |value|
          expect(described_class.completed_transaction_info(value)).to be_nil
        end
      end
    end

    describe "a completed transaction" do
      it "returns a TransactionInfo" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info).to be_a(described_class::TransactionInfo)
      end

      it "returns the exact transaction_id" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info.transaction_id).to eq(transaction.id)
      end

      it "returns the exact listing_id" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info.listing_id).to eq(listing.id)
      end

      it "returns the exact buyer_id" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info.buyer_id).to eq(buyer.id)
      end

      it "returns the exact seller_id" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info.seller_id).to eq(seller.id)
      end

      it "returns the exact completed_at" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info.completed_at).to eq(transaction.completed_at)
      end

      it "does not expose status" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info).not_to respond_to(:status)
      end

      it "is not the underlying ActiveRecord object" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info).not_to be_a(Marketplace::Transaction)
      end

      it "does not respond to save" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info).not_to respond_to(:save)
      end

      it "does not respond to save!" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info).not_to respond_to(:save!)
      end

      it "does not respond to update" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info).not_to respond_to(:update)
      end

      it "does not respond to update!" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info).not_to respond_to(:update!)
      end

      it "exposes no setter for any contract field" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)
        expect(info).not_to respond_to(:transaction_id=)
        expect(info).not_to respond_to(:listing_id=)
        expect(info).not_to respond_to(:buyer_id=)
        expect(info).not_to respond_to(:seller_id=)
        expect(info).not_to respond_to(:completed_at=)
      end

      it "remains unchanged if the underlying transaction record is later mutated in memory" do
        transaction = build_completed
        info = described_class.completed_transaction_info(transaction.id)

        transaction.buyer_id = buyer.id + 999_999
        transaction.completed_at = 1.year.from_now

        expect(info.buyer_id).to eq(buyer.id)
        expect(info.completed_at).not_to eq(transaction.completed_at)
      end

      it "resolves repeated purchases on the same listing independently" do
        first = build_completed
        second = build_completed

        first_info = described_class.completed_transaction_info(first.id)
        second_info = described_class.completed_transaction_info(second.id)

        expect(first_info.transaction_id).to eq(first.id)
        expect(second_info.transaction_id).to eq(second.id)
        expect(first_info.transaction_id).not_to eq(second_info.transaction_id)
        expect(first_info.listing_id).to eq(second_info.listing_id)
        expect(first_info.buyer_id).to eq(second_info.buyer_id)
      end
    end
  end

  describe "public surface" do
    it "exposes exactly one public lookup method" do
      expect(described_class.singleton_methods(false)).to contain_exactly(:completed_transaction_info)
    end

    it "does not expose a generic find/transaction_info API" do
      expect(described_class).not_to respond_to(:find_transaction)
      expect(described_class).not_to respond_to(:transaction_info)
      expect(described_class).not_to respond_to(:find)
      expect(described_class).not_to respond_to(:completed?)
    end
  end

  describe "VERSION" do
    it "is exactly 1" do
      expect(described_class::VERSION).to eq(1)
    end
  end
end
