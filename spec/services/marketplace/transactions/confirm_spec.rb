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

  describe "completion event" do
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

    it "emits zero events for a first confirmation" do
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

      listing = build_listing
      transaction = build_transaction(listing: listing)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(events).to be_empty
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "emits exactly one event, with the scalar transaction id as payload, for the final confirmation" do
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

      listing = build_listing
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(events).to eq([transaction.id])
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "never passes the ActiveRecord transaction object as the payload" do
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

      listing = build_listing
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(events.length).to eq(1)
      expect(events.first).to be_a(Integer)
      expect(events.first).not_to be_a(Marketplace::Transaction)
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "emits zero additional events on completed replay" do
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

      transaction = build_completed_transaction

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(events).to be_empty
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "emits zero events for a same-side pending replay" do
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

      listing = build_listing
      transaction = build_transaction(listing: listing)

      call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(events).to be_empty
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "emits zero events for a confirm attempt on a cancelled transaction" do
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

      transaction =
        build_transaction(status: :cancelled, cancelled_at: Time.current, cancelled_by_id: seller.id)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_failure
      expect(events).to be_empty
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "emits zero events when the final reserve->sold CAS fails and the transaction rolls back" do
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

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

      expect(events).to be_empty
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "fires only once the transaction is durably committed and observable through TradeContract" do
      observed = nil
      handler =
        Proc.new do |transaction_id|
          observed = Marketplace::TradeContract.completed_transaction_info(transaction_id)
        end
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

      listing = build_listing
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(observed).to be_a(Marketplace::TradeContract::TransactionInfo)
      expect(observed.transaction_id).to eq(transaction.id)
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "does not turn a successful confirmation into a failure when a listener raises" do
      handler = Proc.new { raise "reputation listener failure" }
      DiscourseEvent.on(:marketplace_transaction_completed, &handler)

      listing = build_listing
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      result = nil
      expect do
        result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)
      end.not_to raise_error

      expect(result).to be_success
      expect(result.transaction.status).to eq("completed")
    ensure
      DiscourseEvent.off(:marketplace_transaction_completed, &handler)
    end

    it "passes continue_on_error: true to DiscourseEvent.trigger" do
      listing = build_listing
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      expect(DiscourseEvent).to receive(:trigger).with(
        :marketplace_transaction_completed,
        transaction.id,
        continue_on_error: true,
      )

      call_service(guardian: buyer.guardian, transaction_id: transaction.id)
    end
  end

  describe "first confirmation event" do
    def with_handler
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_first_confirmed, &handler)
      yield events
    ensure
      DiscourseEvent.off(:marketplace_transaction_first_confirmed, &handler)
    end

    it "emits exactly one event, with the scalar transaction id as payload, for a first confirmation" do
      with_handler do |events|
        listing = build_listing
        transaction = build_transaction(listing: listing)

        result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

        expect(result).to be_success
        expect(events).to eq([transaction.id])
      end
    end

    it "emits zero events for the final (second) confirmation" do
      with_handler do |events|
        listing = build_listing
        transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

        result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

        expect(result).to be_success
        expect(result.transaction.status).to eq("completed")
        expect(events).to be_empty
      end
    end

    it "emits zero events for a same-side replay of an already-recorded first confirmation" do
      with_handler do |events|
        listing = build_listing
        transaction = build_transaction(listing: listing)
        call_service(guardian: buyer.guardian, transaction_id: transaction.id)
        events.clear

        result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

        expect(result).to be_success
        expect(events).to be_empty
      end
    end

    it "emits zero events for a confirm attempt on a cancelled transaction" do
      with_handler do |events|
        listing = build_listing
        transaction =
          build_transaction(
            listing: listing,
            status: :cancelled,
            cancelled_at: Time.current,
            cancelled_by_id: seller.id,
          )

        result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

        expect(result).to be_failure
        expect(events).to be_empty
      end
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

  describe "finite stock" do
    def build_finite_listing(stock_quantity: 2, stock_reserved: 1, stock_sold: 0, status: :active, **overrides)
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

    it "consumes exactly one unit on final confirmation and stays active/purchasable if stock remains" do
      listing = build_finite_listing(stock_quantity: 2, stock_reserved: 1, stock_sold: 0)
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      expect(result.transaction.status).to eq("completed")
      reloaded = listing.reload
      expect(reloaded.stock_reserved).to eq(0)
      expect(reloaded.stock_sold).to eq(1)
      expect(reloaded.status).to eq("active")
      expect(reloaded.purchasable?).to eq(true)
    end

    it "leaves the listing not purchasable once the last unit is consumed, without flipping status" do
      listing = build_finite_listing(stock_quantity: 1, stock_reserved: 1, stock_sold: 0)
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      reloaded = listing.reload
      expect(reloaded.stock_reserved).to eq(0)
      expect(reloaded.stock_sold).to eq(1)
      expect(reloaded.status).to eq("active")
      expect(reloaded.purchasable?).to eq(false)
    end

    it "does not double-consume stock on a completed replay" do
      listing = build_finite_listing(stock_quantity: 2, stock_reserved: 1, stock_sold: 0)
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)
      call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      reloaded = listing.reload
      expect(reloaded.stock_reserved).to eq(0)
      expect(reloaded.stock_sold).to eq(1)
    end

    it "raises TransactionInvariantViolation for a pending transaction whose listing has no reserved stock" do
      listing = build_finite_listing(stock_quantity: 2, stock_reserved: 0, stock_sold: 0)
      transaction = build_transaction(listing: listing)

      expect { call_service(guardian: buyer.guardian, transaction_id: transaction.id) }.to raise_error(
        Marketplace::TransactionInvariantViolation,
      )
    end

    it "raises TransactionInvariantViolation and rolls back when the consume CAS affects zero rows" do
      listing = build_finite_listing(stock_quantity: 2, stock_reserved: 1, stock_sold: 0)
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      allow(Marketplace::Listing).to receive(:where).and_call_original
      allow(Marketplace::Listing).to receive(:where).with(
        id: listing.id,
        inventory_mode: Marketplace::Listing.inventory_modes[:finite],
      ).and_return(Marketplace::Listing.none)

      expect { call_service(guardian: buyer.guardian, transaction_id: transaction.id) }.to raise_error(
        Marketplace::TransactionInvariantViolation,
      )
      reloaded = transaction.reload
      expect(reloaded.status).to eq("pending")
      expect(listing.reload.stock_reserved).to eq(1)
    end
  end

  describe "unlimited stock" do
    def build_unlimited_listing(status: :active, **overrides)
      Fabricate(
        :marketplace_listing,
        seller: seller,
        category: category,
        status: Marketplace::Listing.statuses[status],
        inventory_mode: Marketplace::Listing.inventory_modes[:unlimited],
        **overrides,
      )
    end

    it "increments stock_sold without any capacity gate and stays active/purchasable" do
      listing = build_unlimited_listing(stock_sold: 3)
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      result = call_service(guardian: buyer.guardian, transaction_id: transaction.id)

      expect(result).to be_success
      reloaded = listing.reload
      expect(reloaded.stock_sold).to eq(4)
      expect(reloaded.status).to eq("active")
      expect(reloaded.purchasable?).to eq(true)
    end

    it "allows a second, independent completed transaction on the same listing" do
      listing = build_unlimited_listing
      first_transaction =
        build_transaction(listing: listing, buyer: buyer, seller_confirmed_at: 1.minute.ago)
      call_service(guardian: buyer.guardian, transaction_id: first_transaction.id)

      second_transaction =
        build_transaction(listing: listing, buyer: unrelated_user, seller_confirmed_at: 1.minute.ago)
      result = call_service(guardian: unrelated_user.guardian, transaction_id: second_transaction.id)

      expect(result).to be_success
      expect(listing.reload.stock_sold).to eq(2)
    end
  end
end
