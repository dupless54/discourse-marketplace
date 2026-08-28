# frozen_string_literal: true

describe Marketplace::Listings::Update do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category) { Fabricate(:marketplace_category) }
  fab!(:other_category) { Fabricate(:marketplace_category) }

  before { SiteSetting.marketplace_allowed_currencies = "USD|EUR" }

  let(:listing) do
    Fabricate(:marketplace_listing, seller: seller, category: category, price_cents: 500, currency: "USD")
  end
  let(:guardian) { seller.guardian }
  let(:params) do
    {
      listing_id: listing.id,
      title: "Updated title",
      raw: "Updated details",
      category_id: other_category.id,
      price_cents: 750,
      currency: "eur",
    }
  end

  def call_service(guardian:, params:)
    described_class.call(guardian: guardian, params: params)
  end

  it "updates a listing owned by the current user" do
    result = call_service(guardian: guardian, params: params)

    expect(result).to be_success
    updated = result.listing
    expect(updated.title).to eq("Updated title")
    expect(updated.raw).to eq("Updated details")
    expect(updated.category_id).to eq(other_category.id)
    expect(updated.price_cents).to eq(750)
    expect(updated.currency).to eq("EUR")
  end

  it "cooks the new raw through Listing.cook, so an embedded image is lightbox-wrapped" do
    upload = Fabricate(:upload)
    result =
      call_service(
        guardian: guardian,
        params: params.merge(raw: "Updated photo: #{upload.short_url}"),
      )

    expect(result).to be_success
    expect(result.listing.cooked).to include("lightbox-wrapper")
  end

  it "regenerates cooked from raw" do
    result = call_service(guardian: guardian, params: params)

    expect(result).to be_success
    expect(result.listing.cooked).to be_present
    expect(result.listing.cooked).not_to eq(listing.cooked)
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

  it "fails policy for a non-owner" do
    non_owner = Fabricate(:user, trust_level: TrustLevel[1])
    result = call_service(guardian: non_owner.guardian, params: params)

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_edit_marketplace_listing)
  end

  it "fails policy for a suspended user" do
    suspended_seller =
      Fabricate(:user, suspended_till: 1.year.from_now, suspended_at: Time.zone.now)
    suspended_listing = Fabricate(:marketplace_listing, seller: suspended_seller, category: category)
    result =
      call_service(
        guardian: suspended_seller.guardian,
        params: params.merge(listing_id: suspended_listing.id),
      )

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_edit_marketplace_listing)
  end

  it "fails policy for a silenced user" do
    silenced_seller = Fabricate(:user, silenced_till: 1.year.from_now)
    silenced_listing = Fabricate(:marketplace_listing, seller: silenced_seller, category: category)
    result =
      call_service(
        guardian: silenced_seller.guardian,
        params: params.merge(listing_id: silenced_listing.id),
      )

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_edit_marketplace_listing)
  end

  it "fails with a not found model when the listing does not exist" do
    result = call_service(guardian: guardian, params: params.merge(listing_id: -1))

    expect(result).to be_failure
    expect(result).to fail_to_find_a_model(:listing)
  end

  it "fails with a not found model when the category does not exist" do
    result = call_service(guardian: guardian, params: params.merge(category_id: -1))

    expect(result).to be_failure
    expect(result).to fail_to_find_a_model(:category)
  end

  it "fails model validation when switching to a disabled category" do
    disabled_category = Fabricate(:marketplace_category, enabled: false)
    result =
      call_service(
        guardian: guardian,
        params: params.merge(category_id: disabled_category.id),
      )

    expect(result).to be_failure
    expect(result.listing.errors[:category]).to be_present
  end

  it "allows an unrelated update when the existing category was disabled later" do
    listing.category.update!(enabled: false)
    result =
      call_service(
        guardian: guardian,
        params: params.merge(category_id: listing.category_id),
      )

    expect(result).to be_success
    expect(result.listing.title).to eq("Updated title")
  end

  it "fails the contract when required params are missing" do
    result = call_service(guardian: guardian, params: params.except(:title))

    expect(result).to be_failure
    expect(result).to fail_a_contract
  end

  describe "inventory_mode" do
    it "switches a listing with no transaction history from single to finite" do
      result =
        call_service(
          guardian: guardian,
          params: params.merge(inventory_mode: "finite", stock_quantity: 4),
        )

      expect(result).to be_success
      expect(result.listing.inventory_mode).to eq("finite")
      expect(result.listing.stock_quantity).to eq(4)
    end

    it "allows raising stock_quantity on an existing finite listing with committed stock" do
      finite_listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          inventory_mode: Marketplace::Listing.inventory_modes[:finite],
          stock_quantity: 2,
          stock_reserved: 1,
          stock_sold: 1,
        )
      Fabricate(:marketplace_transaction, listing: finite_listing, status: Marketplace::Transaction.statuses[:pending])

      result =
        call_service(
          guardian: guardian,
          params:
            params.merge(
              listing_id: finite_listing.id,
              inventory_mode: "finite",
              stock_quantity: 10,
            ),
        )

      expect(result).to be_success
      expect(result.listing.stock_quantity).to eq(10)
    end

    it "fails model validation when shrinking stock_quantity below already-committed stock" do
      finite_listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          inventory_mode: Marketplace::Listing.inventory_modes[:finite],
          stock_quantity: 5,
          stock_reserved: 2,
          stock_sold: 2,
        )

      result =
        call_service(
          guardian: guardian,
          params:
            params.merge(listing_id: finite_listing.id, inventory_mode: "finite", stock_quantity: 3),
        )

      expect(result).to be_failure
      expect(result.listing.errors[:stock_quantity]).to be_present
    end

    it "fails model validation when switching inventory_mode after the listing has any transaction" do
      finite_listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          inventory_mode: Marketplace::Listing.inventory_modes[:finite],
          stock_quantity: 5,
        )
      Fabricate(:marketplace_transaction, listing: finite_listing, status: Marketplace::Transaction.statuses[:pending])

      result =
        call_service(
          guardian: guardian,
          params: params.merge(listing_id: finite_listing.id, inventory_mode: "single"),
        )

      expect(result).to be_failure
      expect(result.listing.errors[:inventory_mode]).to be_present
    end
  end

  describe "expires_at" do
    it "sets an expiration on an existing listing" do
      expires_at = 1.week.from_now.change(usec: 0)
      result = call_service(guardian: guardian, params: params.merge(expires_at: expires_at.iso8601))

      expect(result).to be_success
      expect(result.listing.expires_at).to eq(expires_at)
    end

    it "clears an existing expiration when expires_at is omitted" do
      listing.update!(expires_at: 1.week.from_now)

      result = call_service(guardian: guardian, params: params)

      expect(result).to be_success
      expect(result.listing.expires_at).to be_nil
    end
  end
end
