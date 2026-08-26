# frozen_string_literal: true

describe Marketplace::Transactions::Confirm do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:unrelated_user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:staff) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:marketplace_category) }

  def build_listing(status: :reserved, **overrides)
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[status],
      **overrides,
    )
  end

  def build_transaction(
    status: :pending,
    listing: build_listing,
    buyer: self.buyer,
    seller: self.seller,
    buyer_confirmed_at: nil,
    seller_confirmed_at: nil,
    completed_at: nil,
    cancelled_at: nil,
    cancelled_by_id: nil
  )
    Fabricate(
      :marketplace_transaction,
      listing: listing,
      buyer: buyer,
      seller: seller,
      status: Marketplace::Transaction.statuses[status],
      buyer_confirmed_at: buyer_confirmed_at,
      seller_confirmed_at: seller_confirmed_at,
      completed_at: completed_at,
      cancelled_at: cancelled_at,
      cancelled_by_id: cancelled_by_id,
    )
  end

  def call_service(guardian:, transaction_id:)
    described_class.call(guardian: guardian, params: { transaction_id: transaction_id })
  end

  describe "first confirmation" do
    it "lets the buyer confirm first" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      confirmed = result.transaction
      expect(confirmed.buyer_confirmed_at).to be_present
      expect(confirmed.seller_confirmed_at).to be_nil
      expect(confirmed.status).to eq("pending")
      expect(confirmed.completed_at).to be_nil
      expect(listing.reload.status).to eq("reserved")
    end

    it "lets the seller be the first confirmer" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      result = call_service(guardian: seller.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      confirmed = result.transaction
      expect(confirmed.seller_confirmed_at).to be_present
      expect(confirmed.buyer_confirmed_at).to be_nil
      expect(confirmed.status).to eq("pending")
      expect(listing.reload.status).to eq("reserved")
    end
  end

  describe "second confirmation" do
    it "completes the transaction and sells the listing when the buyer confirms after the seller" do
      listing = build_listing
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      completed = result.transaction
      expect(completed.buyer_confirmed_at).to be_present
      expect(completed.seller_confirmed_at).to be_present
      expect(completed.status).to eq("completed")
      expect(completed.completed_at).to be_present
      expect(completed.buyer_confirmed_at).to eq(completed.completed_at)
      expect(listing.reload.status).to eq("sold")
      expect(listing.closed_at).to eq(completed.completed_at)
    end

    it "completes the transaction and sells the listing when the seller confirms after the buyer" do
      listing = build_listing
      transaction = build_transaction(listing: listing, buyer_confirmed_at: 1.minute.ago)

      result = call_service(guardian: seller.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      completed = result.transaction
      expect(completed.seller_confirmed_at).to be_present
      expect(completed.status).to eq("completed")
      expect(completed.completed_at).to be_present
      expect(completed.seller_confirmed_at).to eq(completed.completed_at)
      expect(listing.reload.status).to eq("sold")
      expect(listing.closed_at).to eq(completed.completed_at)
    end
  end

  describe "authorization" do
    it "rejects an anonymous guardian without raising" do
      transaction = build_transaction

      result = nil
      expect do
        result = call_service(guardian: Guardian.new, transaction_id: transaction.id)
      end.not_to raise_error

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_confirm_marketplace_transaction)
      expect(result.transaction).to be_blank
    end

    it "rejects an unrelated user" do
      transaction = build_transaction
      result = call_service(guardian: unrelated_user.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_confirm_marketplace_transaction)
    end

    it "rejects unrelated staff" do
      transaction = build_transaction
      result = call_service(guardian: staff.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_confirm_marketplace_transaction)
    end

    it "rejects a silenced participant" do
      silenced_buyer = Fabricate(:user, silenced_till: 1.year.from_now, trust_level: TrustLevel[1])
      transaction = build_transaction(buyer: silenced_buyer)

      result = call_service(guardian: silenced_buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_confirm_marketplace_transaction)
    end

    it "rejects a suspended participant" do
      suspended_buyer =
        Fabricate(
          :user,
          suspended_till: 1.year.from_now,
          suspended_at: Time.zone.now,
          trust_level: TrustLevel[1],
        )
      transaction = build_transaction(buyer: suspended_buyer)

      result = call_service(guardian: suspended_buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_confirm_marketplace_transaction)
    end
  end

  describe "category independence" do
    it "still allows confirmation after the listing's category becomes disabled" do
      listing = build_listing
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)
      listing.category.update!(enabled: false)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(result.transaction.status).to eq("completed")
    end
  end

  describe "idempotency" do
    it "lets the same buyer confirm twice while pending without changing state" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      first = call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      second = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(second).to be_success
      expect(second.transaction.id).to eq(first.transaction.id)
      expect(second.transaction.buyer_confirmed_at).to eq(first.transaction.buyer_confirmed_at)
      expect(Marketplace::Transaction.where(id: transaction.id).count).to eq(1)
      expect(listing.reload.status).to eq("reserved")
    end

    it "lets the same seller confirm twice while pending without changing state" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      first = call_service(guardian: seller.guardian, transaction_id: transaction.id)
      second = call_service(guardian: seller.guardian, transaction_id: transaction.id)

      expect(second).to be_success
      expect(second.transaction.seller_confirmed_at).to eq(first.transaction.seller_confirmed_at)
      expect(listing.reload.status).to eq("reserved")
    end
  end

  describe "completed replay" do
    def build_completed_transaction(listing: build_listing(status: :sold))
      now = Time.current
      build_transaction(
        status: :completed,
        listing: listing,
        buyer_confirmed_at: now,
        seller_confirmed_at: now,
        completed_at: now,
      )
    end

    it "lets an authorized buyer retry a completed transaction successfully" do
      transaction = build_completed_transaction
      original_buyer_confirmed_at = transaction.buyer_confirmed_at

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(result.transaction.id).to eq(transaction.id)
      expect(result.transaction.buyer_confirmed_at).to eq(original_buyer_confirmed_at)
    end

    it "lets an authorized seller retry a completed transaction successfully" do
      transaction = build_completed_transaction

      result = call_service(guardian: seller.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(result.transaction.id).to eq(transaction.id)
    end

    it "still works after the listing legitimately moves from sold to archived" do
      listing = build_listing(status: :sold)
      transaction = build_completed_transaction(listing: listing)
      listing.update!(status: Marketplace::Listing.statuses[:archived], closed_at: Time.current)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(result.transaction.id).to eq(transaction.id)
    end
  end

  describe "cancelled" do
    it "fails a confirm attempt on a cancelled transaction with the stable marker and no mutation" do
      transaction =
        build_transaction(status: :cancelled, cancelled_at: Time.current, cancelled_by_id: seller.id)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result.transaction_not_confirmable).to eq(true)
      expect(result.transaction).to be_blank
      expect(transaction.reload.status).to eq("cancelled")
    end
  end

  describe "invariants" do
    it "raises TransactionInvariantViolation for a pending transaction whose listing is active" do
      listing = build_listing(status: :active)
      transaction = build_transaction(listing: listing)

      expect { call_service(guardian: buyer.guardian, transaction_id: transaction.id) }.to raise_error(
        Marketplace::TransactionInvariantViolation,
      )
    end

    it "raises TransactionInvariantViolation for a pending transaction whose listing is sold" do
      listing = build_listing(status: :sold)
      transaction = build_transaction(listing: listing)

      expect { call_service(guardian: buyer.guardian, transaction_id: transaction.id) }.to raise_error(
        Marketplace::TransactionInvariantViolation,
      )
    end

    it "raises TransactionInvariantViolation and rolls back when the final reserve->sold CAS affects zero rows" do
      listing = build_listing
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      allow(Marketplace::Listing).to receive(:where).and_call_original
      allow(Marketplace::Listing).to receive(:where).with(
        id: listing.id,
        status: Marketplace::Listing.statuses[:reserved],
      ).and_return(Marketplace::Listing.none)

      expect { call_service(guardian: buyer.guardian, transaction_id: transaction.id) }.to raise_error(
        Marketplace::TransactionInvariantViolation,
      )

      reloaded = transaction.reload
      expect(reloaded.status).to eq("pending")
      expect(reloaded.buyer_confirmed_at).to be_nil
      expect(reloaded.completed_at).to be_nil
      expect(listing.reload.status).to eq("reserved")
    end
  end

  describe "input" do
    it "gives a model-not-found result for a missing transaction" do
      missing_transaction_id = Marketplace::Transaction.maximum(:id).to_i + 1
      result = call_service(guardian: buyer.guardian, transaction_id: missing_transaction_id)

      expect(result).to be_failure
      expect(result).to fail_to_find_a_model(:transaction_record)
    end

    it "fails the contract for a non-positive transaction_id" do
      result = call_service(guardian: buyer.guardian, transaction_id: 0)

      expect(result).to be_failure
      expect(result).to fail_a_contract
    end

    it "fails the contract for an invalid transaction_id" do
      result = call_service(guardian: buyer.guardian, transaction_id: "abc")

      expect(result).to be_failure
      expect(result).to fail_a_contract
    end

    it "ignores any client-provided identity or state fields" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      result =
        described_class.call(
          guardian: buyer.guardian,
          params: {
            transaction_id: transaction.id,
            buyer_id: seller.id,
            seller_id: buyer.id,
            status: Marketplace::Transaction.statuses[:completed],
            completed_at: Time.current,
          },
        )

      expect(result).to be_success
      expect(result.transaction.buyer_confirmed_at).to be_present
      expect(result.transaction.status).to eq("pending")
    end
  end
end
