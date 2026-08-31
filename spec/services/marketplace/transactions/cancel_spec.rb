# frozen_string_literal: true

describe Marketplace::Transactions::Cancel do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:unrelated_user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:staff, :admin)
  fab!(:category, :marketplace_category)

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

  describe "success" do
    it "lets the buyer cancel a pending transaction" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      cancelled = result.transaction
      expect(cancelled.status).to eq("cancelled")
      expect(cancelled.cancelled_at).to be_present
      expect(cancelled.cancelled_by_id).to eq(buyer.id)
      expect(cancelled.completed_at).to be_nil
      expect(listing.reload.status).to eq("active")
      expect(Marketplace::Transaction.where(id: transaction.id).count).to eq(1)
    end

    it "lets the seller cancel a pending transaction" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      result = call_service(guardian: seller.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      cancelled = result.transaction
      expect(cancelled.status).to eq("cancelled")
      expect(cancelled.cancelled_by_id).to eq(seller.id)
      expect(listing.reload.status).to eq("active")
    end
  end

  describe "staff override" do
    it "lets unrelated staff cancel a pending transaction" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      result = call_service(guardian: staff.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(result.transaction.cancelled_by_id).to eq(staff.id)
      expect(listing.reload.status).to eq("active")
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
      expect(result).to fail_a_policy(:can_cancel_marketplace_transaction)
      expect(result.transaction).to be_blank
    end

    it "rejects an unrelated ordinary user" do
      transaction = build_transaction
      result = call_service(guardian: unrelated_user.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_cancel_marketplace_transaction)
      expect(result.transaction).to be_blank
    end

    it "rejects a silenced non-staff participant" do
      silenced_buyer = Fabricate(:user, silenced_till: 1.year.from_now, trust_level: TrustLevel[1])
      transaction = build_transaction(buyer: silenced_buyer)

      result = call_service(guardian: silenced_buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_cancel_marketplace_transaction)
      expect(result.transaction).to be_blank
    end

    it "rejects a suspended non-staff participant" do
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
      expect(result).to fail_a_policy(:can_cancel_marketplace_transaction)
      expect(result.transaction).to be_blank
    end
  end

  describe "category independence" do
    it "still allows participant cancellation after the listing's category becomes disabled" do
      listing = build_listing
      transaction = build_transaction(listing: listing)
      listing.category.update!(enabled: false)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(result.transaction.status).to eq("cancelled")
    end
  end

  describe "prior confirmation history" do
    it "preserves an existing confirmation timestamp when the other participant cancels" do
      listing = build_listing
      transaction = build_transaction(listing: listing, buyer_confirmed_at: 1.minute.ago)
      original_buyer_confirmed_at = transaction.buyer_confirmed_at

      result = call_service(guardian: seller.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      cancelled = result.transaction
      expect(cancelled.status).to eq("cancelled")
      expect(cancelled.buyer_confirmed_at).to eq(original_buyer_confirmed_at)
      expect(cancelled.seller_confirmed_at).to be_nil
      expect(cancelled.completed_at).to be_nil
      expect(cancelled.cancelled_by_id).to eq(seller.id)
      expect(listing.reload.status).to eq("active")
    end
  end

  describe "idempotency" do
    it "lets the same actor cancel twice as a successful no-op replay" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      first = call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      second = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(second).to be_success
      expect(second.transaction.id).to eq(first.transaction.id)
      expect(second.transaction.cancelled_at).to eq(first.transaction.cancelled_at)
      expect(second.transaction.cancelled_by_id).to eq(first.transaction.cancelled_by_id)
      expect(listing.reload.status).to eq("active")
      expect(Marketplace::Transaction.where(id: transaction.id).count).to eq(1)
    end

    it "lets the other participant retry Cancel without overwriting who originally cancelled" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      first = call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      second = call_service(guardian: seller.guardian, transaction_id: transaction.id)

      expect(second).to be_success
      expect(second.transaction.cancelled_by_id).to eq(buyer.id)
      expect(second.transaction.cancelled_at).to eq(first.transaction.cancelled_at)
      expect(listing.reload.status).to eq("active")
    end

    it "lets unrelated staff retry Cancel without overwriting the original cancellation metadata" do
      listing = build_listing
      transaction = build_transaction(listing: listing)

      first = call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      second = call_service(guardian: staff.guardian, transaction_id: transaction.id)

      expect(second).to be_success
      expect(second.transaction.cancelled_by_id).to eq(buyer.id)
      expect(second.transaction.cancelled_at).to eq(first.transaction.cancelled_at)
    end
  end

  describe "old-cancel replay after a new transaction exists" do
    it "does not disturb a newer pending transaction or reactivate its reserved listing" do
      listing = build_listing
      transaction_a = build_transaction(listing: listing)

      cancel_a_result = call_service(guardian: buyer.guardian, transaction_id: transaction_a.id)
      expect(cancel_a_result).to be_success
      expect(listing.reload.status).to eq("active")

      other_buyer = Fabricate(:user, trust_level: TrustLevel[1])
      create_result =
        Marketplace::Transactions::Create.call(
          guardian: other_buyer.guardian,
          params: {
            listing_id: listing.id,
          },
        )
      expect(create_result).to be_success
      transaction_b = create_result.transaction
      expect(listing.reload.status).to eq("reserved")
      expect(transaction_b.status).to eq("pending")

      replay_result = call_service(guardian: buyer.guardian, transaction_id: transaction_a.id)

      expect(replay_result).to be_success
      expect(replay_result.transaction.id).to eq(transaction_a.id)
      expect(replay_result.transaction.status).to eq("cancelled")
      expect(listing.reload.status).to eq("reserved")
      expect(transaction_b.reload.status).to eq("pending")
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(2)
    end
  end

  describe "completed" do
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

    it "fails a buyer's attempt to cancel a completed transaction" do
      transaction = build_completed_transaction

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result.transaction_not_cancellable).to eq(true)
      expect(result.transaction).to be_blank
      expect(transaction.reload.status).to eq("completed")
    end

    it "fails unrelated staff's attempt to cancel a completed transaction" do
      transaction = build_completed_transaction

      result = call_service(guardian: staff.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(result.transaction_not_cancellable).to eq(true)
      expect(result.transaction).to be_blank
    end
  end

  describe "invariants" do
    it "raises TransactionInvariantViolation for a pending transaction whose listing is active" do
      listing = build_listing(status: :active)
      transaction = build_transaction(listing: listing)

      expect {
        call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      }.to raise_error(Marketplace::TransactionInvariantViolation)
    end

    it "raises TransactionInvariantViolation for a pending transaction whose listing is sold" do
      listing = build_listing(status: :sold)
      transaction = build_transaction(listing: listing)

      expect {
        call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      }.to raise_error(Marketplace::TransactionInvariantViolation)
    end

    it "raises TransactionInvariantViolation and rolls back when the reserved->active CAS affects zero rows" do
      listing = build_listing
      transaction = build_transaction(listing: listing, buyer_confirmed_at: 1.minute.ago)

      allow(Marketplace::Listing).to receive(:where).and_call_original
      allow(Marketplace::Listing).to receive(:where).with(
        id: listing.id,
        status: Marketplace::Listing.statuses[:reserved],
      ).and_return(Marketplace::Listing.none)

      expect {
        call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      }.to raise_error(Marketplace::TransactionInvariantViolation)

      reloaded = transaction.reload
      expect(reloaded.status).to eq("pending")
      expect(reloaded.cancelled_at).to be_nil
      expect(reloaded.cancelled_by_id).to be_nil
      expect(reloaded.buyer_confirmed_at).to be_present
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
            cancelled_by_id: seller.id,
            cancelled_at: 1.year.ago,
            status: Marketplace::Transaction.statuses[:completed],
            listing_id: -1,
          },
        )

      expect(result).to be_success
      expect(result.transaction.cancelled_by_id).to eq(buyer.id)
      expect(result.transaction.cancelled_at).to be_within(5.seconds).of(Time.current)
    end
  end

  describe "cancelled event" do
    def with_handler
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_cancelled, &handler)
      yield events
    ensure
      DiscourseEvent.off(:marketplace_transaction_cancelled, &handler)
    end

    it "emits exactly one event, with the scalar transaction id as payload, on a real cancel" do
      with_handler do |events|
        transaction = build_transaction
        result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

        expect(result).to be_success
        expect(events).to eq([transaction.id])
      end
    end

    it "emits zero events on a cancelled replay" do
      with_handler do |events|
        transaction = build_transaction
        call_service(guardian: buyer.guardian, transaction_id: transaction.id)
        events.clear

        result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

        expect(result).to be_success
        expect(events).to be_empty
      end
    end

    it "emits zero events when cancelling a completed transaction is rejected" do
      with_handler do |events|
        now = Time.current
        transaction =
          build_transaction(
            status: :completed,
            listing: build_listing(status: :sold),
            buyer_confirmed_at: now,
            seller_confirmed_at: now,
            completed_at: now,
          )

        result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

        expect(result).to be_failure
        expect(events).to be_empty
      end
    end
  end

  describe "finite stock" do
    def build_finite_listing(
      stock_quantity: 2,
      stock_reserved: 1,
      stock_sold: 0,
      status: :active,
      **overrides
    )
      Fabricate(
        :marketplace_listing,
        seller: seller,
        category: category,
        status: Marketplace::Listing.statuses[status],
        inventory_mode: Marketplace::Listing.inventory_modes[:finite],
        stock_quantity: stock_quantity,
        stock_reserved: stock_reserved,
        stock_sold: stock_sold,
        **overrides,
      )
    end

    it "releases exactly the one unit this transaction held, leaving listing.status untouched" do
      listing = build_finite_listing(stock_quantity: 2, stock_reserved: 1, stock_sold: 0)
      transaction = build_transaction(listing: listing)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      reloaded = listing.reload
      expect(reloaded.stock_reserved).to eq(0)
      expect(reloaded.status).to eq("active")
      expect(reloaded.purchasable?).to eq(true)
    end

    it "does not release a unit twice when the same cancellation is replayed" do
      listing = build_finite_listing(stock_quantity: 2, stock_reserved: 2, stock_sold: 0)
      transaction_a =
        Fabricate(
          :marketplace_transaction,
          listing: listing,
          buyer: buyer,
          seller: seller,
          status: Marketplace::Transaction.statuses[:pending],
        )
      Fabricate(
        :marketplace_transaction,
        listing: listing,
        buyer: unrelated_user,
        seller: seller,
        status: Marketplace::Transaction.statuses[:pending],
      )

      first = call_service(guardian: buyer.guardian, transaction_id: transaction_a.id)
      second = call_service(guardian: buyer.guardian, transaction_id: transaction_a.id)

      expect(first).to be_success
      expect(second).to be_success
      expect(listing.reload.stock_reserved).to eq(1)
    end

    it "lets a listing become purchasable again after a cancellation frees the last unit" do
      listing = build_finite_listing(stock_quantity: 1, stock_reserved: 1, stock_sold: 0)
      transaction = build_transaction(listing: listing)

      call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(listing.reload.purchasable?).to eq(true)
    end

    it "raises TransactionInvariantViolation for a pending transaction whose listing has no reserved stock" do
      listing = build_finite_listing(stock_quantity: 2, stock_reserved: 0, stock_sold: 0)
      transaction = build_transaction(listing: listing)

      expect {
        call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      }.to raise_error(Marketplace::TransactionInvariantViolation)
    end

    it "raises TransactionInvariantViolation and rolls back when the release CAS affects zero rows" do
      listing = build_finite_listing(stock_quantity: 2, stock_reserved: 1, stock_sold: 0)
      transaction = build_transaction(listing: listing, buyer_confirmed_at: 1.minute.ago)

      allow(Marketplace::Listing).to receive(:where).and_call_original
      allow(Marketplace::Listing).to receive(:where).with(
        id: listing.id,
        inventory_mode: Marketplace::Listing.inventory_modes[:finite],
      ).and_return(Marketplace::Listing.none)

      expect {
        call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      }.to raise_error(Marketplace::TransactionInvariantViolation)
      reloaded = transaction.reload
      expect(reloaded.status).to eq("pending")
      expect(reloaded.cancelled_at).to be_nil
      expect(listing.reload.stock_reserved).to eq(1)
    end
  end

  describe "unlimited stock" do
    it "is a no-op release (nothing was ever reserved)" do
      listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
          inventory_mode: Marketplace::Listing.inventory_modes[:unlimited],
        )
      transaction = build_transaction(listing: listing)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      reloaded = listing.reload
      expect(reloaded.stock_sold).to eq(0)
      expect(reloaded.status).to eq("active")
      expect(reloaded.purchasable?).to eq(true)
    end
  end
end
