# frozen_string_literal: true

describe Marketplace::Transactions::Create do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:other_buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category) { Fabricate(:marketplace_category) }

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
      disabled_category = Fabricate(:marketplace_category, enabled: false)
      listing = build_listing(category: disabled_category)
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
      expect { result = call_service(guardian: Guardian.new, listing_id: listing.id) }.not_to raise_error

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
end
