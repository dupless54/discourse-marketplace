# frozen_string_literal: true

describe Marketplace::Listings::Create do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category) { Fabricate(:marketplace_category) }

  before { SiteSetting.marketplace_allowed_currencies = "USD|EUR" }

  let(:guardian) { seller.guardian }
  let(:params) do
    {
      title: "A great listing",
      raw: "Details here",
      category_id: category.id,
      price_cents: 500,
      currency: "usd",
    }
  end

  def call_service(guardian:, params:)
    described_class.call(guardian: guardian, params: params)
  end

  it "creates a draft listing owned by the current user" do
    result = call_service(guardian: guardian, params: params)

    expect(result).to be_success
    listing = result.listing
    expect(listing).to be_persisted
    expect(listing.seller_id).to eq(seller.id)
    expect(listing.status).to eq("draft")
    expect(listing.currency).to eq("USD")
    expect(listing.cooked).to be_present
  end

  it "ignores a client-supplied seller_id and status" do
    other_user = Fabricate(:user)
    result =
      call_service(
        guardian: guardian,
        params: params.merge(seller_id: other_user.id, status: 30),
      )

    expect(result).to be_success
    expect(result.listing.seller_id).to eq(seller.id)
    expect(result.listing.status).to eq("draft")
  end

  it "fails policy for an anonymous user" do
    result = call_service(guardian: Guardian.new, params: params)

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_create_marketplace_listing)
  end

  it "fails policy for a user below the minimum trust level" do
    SiteSetting.marketplace_min_trust_level = 2
    result = call_service(guardian: guardian, params: params)

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_create_marketplace_listing)
  end

  it "fails policy for a suspended user" do
    suspended_user = Fabricate(:user, suspended_till: 1.year.from_now, suspended_at: Time.zone.now)
    result = call_service(guardian: suspended_user.guardian, params: params)

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_create_marketplace_listing)
  end

  it "fails policy for a silenced user" do
    silenced_user = Fabricate(:user, silenced_till: 1.year.from_now)
    result = call_service(guardian: silenced_user.guardian, params: params)

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_create_marketplace_listing)
  end

  it "fails with a not found model when the category does not exist" do
    result = call_service(guardian: guardian, params: params.merge(category_id: -1))

    expect(result).to be_failure
    expect(result).to fail_to_find_a_model(:category)
  end

  it "fails model validation when the category is disabled" do
    disabled_category = Fabricate(:marketplace_category, enabled: false)
    result =
      call_service(
        guardian: guardian,
        params: params.merge(category_id: disabled_category.id),
      )

    expect(result).to be_failure
    expect(result.listing.errors[:category]).to be_present
  end

  it "fails the contract when required params are missing" do
    result = call_service(guardian: guardian, params: params.except(:title))

    expect(result).to be_failure
    expect(result).to fail_a_contract
  end

  describe "inventory_mode" do
    it "defaults to single when omitted" do
      result = call_service(guardian: guardian, params: params)

      expect(result).to be_success
      expect(result.listing.inventory_mode).to eq("single")
      expect(result.listing.stock_quantity).to be_nil
    end

    it "creates a finite listing with the given stock_quantity" do
      result =
        call_service(
          guardian: guardian,
          params: params.merge(inventory_mode: "finite", stock_quantity: 5),
        )

      expect(result).to be_success
      expect(result.listing.inventory_mode).to eq("finite")
      expect(result.listing.stock_quantity).to eq(5)
    end

    it "creates an unlimited listing with no stock_quantity" do
      result = call_service(guardian: guardian, params: params.merge(inventory_mode: "unlimited"))

      expect(result).to be_success
      expect(result.listing.inventory_mode).to eq("unlimited")
      expect(result.listing.stock_quantity).to be_nil
    end

    it "fails the contract for finite without a stock_quantity" do
      result = call_service(guardian: guardian, params: params.merge(inventory_mode: "finite"))

      expect(result).to be_failure
      expect(result).to fail_a_contract
    end

    it "fails the contract for finite with a zero stock_quantity" do
      result =
        call_service(
          guardian: guardian,
          params: params.merge(inventory_mode: "finite", stock_quantity: 0),
        )

      expect(result).to be_failure
      expect(result).to fail_a_contract
    end

    it "fails the contract for an unrecognized inventory_mode" do
      result = call_service(guardian: guardian, params: params.merge(inventory_mode: "bogus"))

      expect(result).to be_failure
      expect(result).to fail_a_contract
    end

    it "ignores a stray stock_quantity for a single-mode listing" do
      result =
        call_service(
          guardian: guardian,
          params: params.merge(inventory_mode: "single", stock_quantity: 5),
        )

      expect(result).to be_success
      expect(result.listing.stock_quantity).to be_nil
    end
  end

  describe "expires_at" do
    it "defaults to no expiration" do
      result = call_service(guardian: guardian, params: params)

      expect(result).to be_success
      expect(result.listing.expires_at).to be_nil
    end

    it "accepts an ISO8601 expiration timestamp" do
      expires_at = 1.week.from_now.change(usec: 0)
      result = call_service(guardian: guardian, params: params.merge(expires_at: expires_at.iso8601))

      expect(result).to be_success
      expect(result.listing.expires_at).to eq(expires_at)
    end
  end
end
