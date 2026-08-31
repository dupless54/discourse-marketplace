# frozen_string_literal: true

describe Marketplace::Transactions::Create do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:other_buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category, :marketplace_category)

  def build_listing(status: :active, **overrides)
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[status],
      **overrides,
    )
  end

  def call_service(guardian:, listing_id:)
    described_class.call(guardian: guardian, params: { listing_id: listing_id })
  end

  def build_finite_listing(
    stock_quantity: 2,
    stock_reserved: 0,
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

  describe "success" do
    it "creates exactly one pending transaction and reserves the listing together" do
      listing = build_listing
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_success
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(1)

      transaction = result.transaction
      expect(transaction.status).to eq("pending")
      expect(transaction.listing).to eq(listing)
      expect(transaction.buyer_id).to eq(buyer.id)
      expect(transaction.seller_id).to eq(listing.seller_id)
      expect(listing.reload.status).to eq("reserved")
    end
  end

  describe "snapshot" do
    it "captures the listing's title, price, and currency at creation time" do
      listing = build_listing(title: "Widget", price_cents: 2500, currency: "USD")
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_success
      expect(result.transaction.listing_title_snapshot).to eq("Widget")
      expect(result.transaction.price_cents_snapshot).to eq(2500)
      expect(result.transaction.currency_snapshot).to eq("USD")
    end

    it "does not rewrite the snapshot on a same-buyer replay, even if the listing changed since" do
      listing = build_listing(title: "Widget", price_cents: 2500, currency: "USD")
      first = call_service(guardian: buyer.guardian, listing_id: listing.id)

      listing.update!(title: "Widget 2", price_cents: 5000)

      second = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(second.transaction.id).to eq(first.transaction.id)
      expect(second.transaction.listing_title_snapshot).to eq("Widget")
      expect(second.transaction.price_cents_snapshot).to eq(2500)
      expect(second.transaction.currency_snapshot).to eq("USD")
    end

    it "ignores client-provided snapshot fields" do
      listing = build_listing(title: "Widget", price_cents: 2500, currency: "USD")
      result =
        described_class.call(
          guardian: buyer.guardian,
          params: {
            listing_id: listing.id,
            listing_title_snapshot: "Hacked",
            price_cents_snapshot: 1,
            currency_snapshot: "XXX",
          },
        )

      expect(result).to be_success
      expect(result.transaction.listing_title_snapshot).to eq("Widget")
      expect(result.transaction.price_cents_snapshot).to eq(2500)
      expect(result.transaction.currency_snapshot).to eq("USD")
    end
  end

  describe "eligibility" do
    it "rejects self-trade" do
      listing = build_listing
      result = call_service(guardian: seller.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "rejects an anonymous guardian" do
      listing = build_listing
      result = call_service(guardian: Guardian.new, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "rejects a silenced buyer" do
      silenced = Fabricate(:user, silenced_till: 1.year.from_now, trust_level: TrustLevel[1])
      listing = build_listing
      result = call_service(guardian: silenced.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "rejects a suspended buyer" do
      suspended =
        Fabricate(
          :user,
          suspended_till: 1.year.from_now,
          suspended_at: Time.zone.now,
          trust_level: TrustLevel[1],
        )
      listing = build_listing
      result = call_service(guardian: suspended.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "rejects a draft listing" do
      listing = build_listing(status: :draft)
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "rejects a reserved listing with no existing pending transaction" do
      listing = build_listing(status: :reserved)
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "keeps SINGLE one-sale behavior after completion" do
      listing = build_listing(status: :sold)
      now = Time.current
      completed =
        Fabricate(
          :marketplace_transaction,
          listing: listing,
          buyer: buyer,
          seller: seller,
          status: Marketplace::Transaction.statuses[:completed],
          buyer_confirmed_at: now,
          seller_confirmed_at: now,
          completed_at: now,
        )

      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
      expect(Marketplace::Transaction.where(listing_id: listing.id).pluck(:id)).to eq(
        [completed.id],
      )
      expect(listing.reload.status).to eq("sold")
    end

    it "rejects a sold listing" do
      listing = build_listing(status: :sold)
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "rejects an archived listing" do
      listing = build_listing(status: :archived)
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "rejects a listing in a disabled category" do
      listing = build_listing
      listing.category.update!(enabled: false)
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end
  end

  describe "idempotency" do
    it "returns the exact same transaction on a same-buyer retry without creating a new row" do
      listing = build_listing
      first = call_service(guardian: buyer.guardian, listing_id: listing.id)
      second = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(second).to be_success
      expect(second.transaction.id).to eq(first.transaction.id)
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(1)
      expect(listing.reload.status).to eq("reserved")
    end

    it "still returns the same transaction after the category becomes disabled" do
      listing = build_listing
      first = call_service(guardian: buyer.guardian, listing_id: listing.id)
      listing.category.update!(enabled: false)

      second = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(second).to be_success
      expect(second.transaction.id).to eq(first.transaction.id)
    end
  end

  describe "contention" do
    it "fails a different buyer with the generic listing_unavailable marker and leaks no details" do
      listing = build_listing
      call_service(guardian: buyer.guardian, listing_id: listing.id)

      result = call_service(guardian: other_buyer.guardian, listing_id: listing.id)

      expect(result.failure?).to eq(true)
      expect(result.listing_unavailable).to eq(true)
      expect(result.transaction).to be_blank
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(1)
    end

    it "fails a RecordNotUnique race with the same listing_unavailable marker and rolls back" do
      listing = build_listing
      allow_any_instance_of(Marketplace::Transaction).to receive(:save!).and_raise(
        ActiveRecord::RecordNotUnique.new("duplicate key"),
      )

      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result.failure?).to eq(true)
      expect(result.listing_unavailable).to eq(true)
      expect(result.transaction).to be_blank
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(0)
      expect(listing.reload.status).to eq("active")
    end

    it "fails an anonymous guardian against an existing pending transaction without raising" do
      listing = build_listing
      call_service(guardian: buyer.guardian, listing_id: listing.id)

      result = nil
      expect {
        result = call_service(guardian: Guardian.new, listing_id: listing.id)
      }.not_to raise_error

      expect(result.failure?).to eq(true)
      expect(result.listing_unavailable).to eq(true)
      expect(result.transaction).to be_blank
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(1)
      expect(listing.reload.status).to eq("reserved")
    end
  end

  describe "invariants" do
    it "raises TransactionInvariantViolation when a same-buyer pending transaction exists but the listing is not reserved" do
      listing = build_listing
      Fabricate(
        :marketplace_transaction,
        listing: listing,
        buyer: buyer,
        seller: seller,
        status: Marketplace::Transaction.statuses[:pending],
      )
      listing.update_columns(status: Marketplace::Listing.statuses[:active])

      expect { call_service(guardian: buyer.guardian, listing_id: listing.id) }.to raise_error(
        Marketplace::TransactionInvariantViolation,
      )
    end

    it "raises TransactionInvariantViolation and rolls back when the reserve CAS affects zero rows" do
      listing = build_listing
      allow(Marketplace::Listing).to receive(:where).and_call_original
      allow(Marketplace::Listing).to receive(:where).with(
        id: listing.id,
        status: Marketplace::Listing.statuses[:active],
      ).and_return(Marketplace::Listing.none)

      expect { call_service(guardian: buyer.guardian, listing_id: listing.id) }.to raise_error(
        Marketplace::TransactionInvariantViolation,
      )
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(0)
    end
  end

  describe "input" do
    it "gives a model-not-found result for a missing listing" do
      missing_listing_id = Marketplace::Listing.maximum(:id).to_i + 1
      result = call_service(guardian: buyer.guardian, listing_id: missing_listing_id)

      expect(result).to be_failure
      expect(result).to fail_to_find_a_model(:listing)
    end

    it "fails the contract for a non-positive listing_id" do
      result = call_service(guardian: buyer.guardian, listing_id: 0)

      expect(result).to be_failure
      expect(result).to fail_a_contract
    end

    it "fails the contract for an invalid listing_id" do
      result = call_service(guardian: buyer.guardian, listing_id: "abc")

      expect(result).to be_failure
      expect(result).to fail_a_contract
    end

    it "ignores any client-provided identity or status fields" do
      listing = build_listing
      result =
        described_class.call(
          guardian: buyer.guardian,
          params: {
            listing_id: listing.id,
            buyer_id: seller.id,
            seller_id: buyer.id,
            status: Marketplace::Transaction.statuses[:completed],
          },
        )

      expect(result).to be_success
      expect(result.transaction.buyer_id).to eq(buyer.id)
      expect(result.transaction.seller_id).to eq(seller.id)
      expect(result.transaction.status).to eq("pending")
    end
  end

  describe "created event" do
    def with_handler
      events = []
      handler = Proc.new { |transaction_id| events << transaction_id }
      DiscourseEvent.on(:marketplace_transaction_created, &handler)
      yield events
    ensure
      DiscourseEvent.off(:marketplace_transaction_created, &handler)
    end

    it "emits exactly one event, with the scalar transaction id as payload, on a real create" do
      with_handler do |events|
        listing = build_listing
        result = call_service(guardian: buyer.guardian, listing_id: listing.id)

        expect(result).to be_success
        expect(events).to eq([result.transaction.id])
      end
    end

    it "emits zero events on a same-buyer replay" do
      with_handler do |events|
        listing = build_listing
        call_service(guardian: buyer.guardian, listing_id: listing.id)
        events.clear

        result = call_service(guardian: buyer.guardian, listing_id: listing.id)

        expect(result).to be_success
        expect(events).to be_empty
      end
    end

    it "emits zero events when a different buyer is rejected for contention" do
      with_handler do |events|
        listing = build_listing
        call_service(guardian: buyer.guardian, listing_id: listing.id)
        events.clear

        result = call_service(guardian: other_buyer.guardian, listing_id: listing.id)

        expect(result).to be_failure
        expect(events).to be_empty
      end
    end
  end

  describe "finite stock" do
    it "lets two different buyers each hold a concurrent pending transaction" do
      listing = build_finite_listing(stock_quantity: 2)

      first = call_service(guardian: buyer.guardian, listing_id: listing.id)
      second = call_service(guardian: other_buyer.guardian, listing_id: listing.id)

      expect(first).to be_success
      expect(second).to be_success
      expect(first.transaction.id).not_to eq(second.transaction.id)
      expect(listing.reload.stock_reserved).to eq(2)
      expect(listing.status).to eq("active")
    end

    it "rejects a third buyer once stock is fully reserved" do
      listing = build_finite_listing(stock_quantity: 1)
      call_service(guardian: buyer.guardian, listing_id: listing.id)

      result = call_service(guardian: other_buyer.guardian, listing_id: listing.id)

      expect(result.failure?).to eq(true)
      expect(result.listing_unavailable).to eq(true)
      expect(listing.reload.stock_reserved).to eq(1)
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(1)
    end

    it "excludes stock already permanently sold from availability" do
      listing = build_finite_listing(stock_quantity: 1, stock_sold: 1)

      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result.failure?).to eq(true)
      expect(result.listing_unavailable).to eq(true)
    end

    it "returns the exact same transaction on a same-buyer retry without double-reserving" do
      listing = build_finite_listing(stock_quantity: 2)
      first = call_service(guardian: buyer.guardian, listing_id: listing.id)
      second = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(second.transaction.id).to eq(first.transaction.id)
      expect(listing.reload.stock_reserved).to eq(1)
    end

    it "lets the same buyer purchase again after completion while preserving history" do
      listing = build_finite_listing(stock_quantity: 2, stock_sold: 1)
      now = Time.current
      completed =
        Fabricate(
          :marketplace_transaction,
          listing: listing,
          buyer: buyer,
          seller: seller,
          status: Marketplace::Transaction.statuses[:completed],
          buyer_confirmed_at: now,
          seller_confirmed_at: now,
          completed_at: now,
        )

      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_success
      expect(result.transaction.id).not_to eq(completed.id)
      expect(result.transaction.status).to eq("pending")
      expect(completed.reload.status).to eq("completed")
      expect(listing.reload.stock_reserved).to eq(1)
      expect(listing.stock_sold).to eq(1)
    end

    it "lets the same buyer purchase again after cancellation" do
      listing = build_finite_listing(stock_quantity: 2)
      cancelled =
        Fabricate(
          :marketplace_transaction,
          listing: listing,
          buyer: buyer,
          seller: seller,
          status: Marketplace::Transaction.statuses[:cancelled],
          cancelled_at: Time.current,
          cancelled_by_id: buyer.id,
        )

      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_success
      expect(result.transaction.id).not_to eq(cancelled.id)
      expect(cancelled.reload.status).to eq("cancelled")
      expect(listing.reload.stock_reserved).to eq(1)
    end

    it "rejects a draft finite listing with a plain policy failure, not listing_unavailable" do
      listing = build_finite_listing(status: :draft, stock_quantity: 2)
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
      expect(result.listing_unavailable).to be_blank
    end

    it "rejects an expired finite listing with a plain policy failure" do
      listing = build_finite_listing(stock_quantity: 2, expires_at: 1.hour.ago)
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end

    it "raises TransactionInvariantViolation and rolls back when the reserve CAS affects zero rows" do
      listing = build_finite_listing(stock_quantity: 1)

      allow(Marketplace::Listing).to receive(:where).and_call_original
      allow(Marketplace::Listing).to receive(:where).with(
        id: listing.id,
        status: Marketplace::Listing.statuses[:active],
      ).and_return(Marketplace::Listing.none)

      expect { call_service(guardian: buyer.guardian, listing_id: listing.id) }.to raise_error(
        Marketplace::TransactionInvariantViolation,
      )
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(0)
    end
  end

  describe "unlimited stock" do
    it "lets many different buyers each hold a concurrent pending transaction" do
      listing = build_unlimited_listing

      first = call_service(guardian: buyer.guardian, listing_id: listing.id)
      second = call_service(guardian: other_buyer.guardian, listing_id: listing.id)

      expect(first).to be_success
      expect(second).to be_success
      expect(listing.reload.status).to eq("active")
    end

    it "returns the exact same transaction on a same-buyer retry" do
      listing = build_unlimited_listing
      first = call_service(guardian: buyer.guardian, listing_id: listing.id)
      second = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(second.transaction.id).to eq(first.transaction.id)
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(1)
    end

    it "lets the same buyer purchase again after completion" do
      listing = build_unlimited_listing(stock_sold: 1)
      now = Time.current
      completed =
        Fabricate(
          :marketplace_transaction,
          listing: listing,
          buyer: buyer,
          seller: seller,
          status: Marketplace::Transaction.statuses[:completed],
          buyer_confirmed_at: now,
          seller_confirmed_at: now,
          completed_at: now,
        )

      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_success
      expect(result.transaction.id).not_to eq(completed.id)
      expect(completed.reload.status).to eq("completed")
      expect(
        Marketplace::Transaction.where(listing_id: listing.id, buyer_id: buyer.id).count,
      ).to eq(2)
    end

    it "rejects an expired unlimited listing with a plain policy failure" do
      listing = build_unlimited_listing(expires_at: 1.hour.ago)
      result = call_service(guardian: buyer.guardian, listing_id: listing.id)

      expect(result).to be_failure
      expect(result).to fail_a_policy(:can_create_marketplace_transaction)
    end
  end

  describe "concurrent final-unit purchase protection" do
    # Real race, not a sequential replay: N threads each drive the full
    # service concurrently against a single finite unit. Whichever thread's
    # atomic guarded UPDATE (see Transactions::Create#reserve_finite_capacity)
    # wins, the loser must observe a consistent, already-exhausted listing --
    # never double-reserve the same last unit. Mirrors the established
    # multi-thread counter-race pattern already used in this codebase's
    # dependencies (e.g. Llm::QuotaUsage#increment_usage! specs).
    it "never lets two buyers both reserve the last unit of a finite listing" do
      listing = build_finite_listing(stock_quantity: 1)
      buyers = [buyer, other_buyer]
      results = Array.new(2)

      threads =
        buyers.each_with_index.map do |b, i|
          Thread.new { results[i] = call_service(guardian: b.guardian, listing_id: listing.id) }
        end
      threads.each(&:join)

      successes = results.select(&:success?)
      failures = results.reject(&:success?)

      expect(successes.length).to eq(1)
      expect(failures.length).to eq(1)
      expect(failures.first.listing_unavailable).to eq(true)
      expect(listing.reload.stock_reserved).to eq(1)
      expect(
        Marketplace::Transaction.where(
          listing_id: listing.id,
          status: Marketplace::Transaction.statuses[:pending],
        ).count,
      ).to eq(1)
    end
  end
end
