# frozen_string_literal: true

describe "GET /marketplace/transactions/mine" do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:other_buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:other_seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category, :marketplace_category)

  before do
    SiteSetting.marketplace_enabled = true
    SiteSetting.marketplace_allowed_currencies = "USD|EUR"
  end

  def build_listing(seller: self.seller, status: :active, **overrides)
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
    listing: build_listing(status: :reserved),
    buyer: self.buyer,
    seller: self.seller,
    **overrides
  )
    Fabricate(
      :marketplace_transaction,
      listing: listing,
      buyer: buyer,
      seller: seller,
      status: Marketplace::Transaction.statuses[status],
      **overrides,
    )
  end

  def get_mine(params = {})
    get "/marketplace/transactions/mine.json", params: params
  end

  def transaction_ids
    response.parsed_body["transactions"].map { |t| t["id"] }
  end

  describe "authorization" do
    it "rejects anonymous access" do
      get_mine

      expect(response.status).to eq(403)
    end

    it "returns only the current user's own transactions as buyer" do
      mine = build_transaction(buyer: buyer)
      build_transaction(buyer: other_buyer)
      sign_in(buyer)

      get_mine(role: "buyer")

      expect(transaction_ids).to eq([mine.id])
    end

    it "returns only the current user's own transactions as seller" do
      mine = build_transaction(seller: seller)
      other_listing = build_listing(seller: other_seller, status: :reserved)
      build_transaction(seller: other_seller, listing: other_listing, buyer: other_buyer)
      sign_in(seller)

      get_mine(role: "seller")

      expect(transaction_ids).to eq([mine.id])
    end

    it "never leaks another buyer's transactions into the current user's buyer view" do
      build_transaction(buyer: other_buyer)
      sign_in(buyer)

      get_mine(role: "buyer")

      expect(response.parsed_body["transactions"]).to be_empty
    end
  end

  describe "role filter" do
    it "defaults to role=buyer when role is omitted" do
      mine = build_transaction(buyer: buyer)
      sign_in(buyer)

      get_mine

      expect(transaction_ids).to eq([mine.id])
    end

    it "returns 400 for an invalid role" do
      sign_in(buyer)

      get_mine(role: "admin")

      expect(response.status).to eq(400)
    end
  end

  describe "status filter" do
    def build_completed(buyer:)
      now = Time.current
      build_transaction(
        buyer: buyer,
        status: :completed,
        listing: build_listing(status: :sold),
        buyer_confirmed_at: now,
        seller_confirmed_at: now,
        completed_at: now,
      )
    end

    it "filters to only the requested status" do
      build_transaction(buyer: buyer, status: :pending)
      completed = build_completed(buyer: buyer)
      sign_in(buyer)

      get_mine(role: "buyer", status: "completed")

      expect(transaction_ids).to eq([completed.id])
    end

    it "returns 400 for an invalid status" do
      sign_in(buyer)

      get_mine(status: "bogus")

      expect(response.status).to eq(400)
    end
  end

  describe "pagination" do
    it "returns page, per_page, and has_more reflecting the request" do
      Array.new(3) { build_transaction(buyer: buyer, listing: build_listing(status: :reserved)) }
      sign_in(buyer)

      get_mine(role: "buyer", page: 1, per_page: 2)

      pagination = response.parsed_body["pagination"]
      expect(pagination["page"]).to eq(1)
      expect(pagination["per_page"]).to eq(2)
      expect(pagination["has_more"]).to eq(true)
      expect(response.parsed_body["transactions"].size).to eq(2)
    end

    it "clamps per_page above 50 to 50" do
      build_transaction(buyer: buyer)
      sign_in(buyer)

      get_mine(per_page: 500)

      expect(response.parsed_body["pagination"]["per_page"]).to eq(50)
    end

    it "returns 400 for invalid page/per_page" do
      sign_in(buyer)

      get_mine(page: 0)
      expect(response.status).to eq(400)

      get_mine(per_page: -1)
      expect(response.status).to eq(400)

      get_mine(page: "abc")
      expect(response.status).to eq(400)
    end
  end

  describe "ordering" do
    it "orders newest first, deterministically" do
      older = build_transaction(buyer: buyer, listing: build_listing(status: :reserved))
      older.update_columns(created_at: 2.days.ago)
      newer = build_transaction(buyer: buyer, listing: build_listing(status: :reserved))
      newer.update_columns(created_at: 1.day.ago)
      sign_in(buyer)

      get_mine(role: "buyer")

      expect(transaction_ids).to eq([newer.id, older.id])
    end
  end

  describe "serializer fields" do
    it "includes exactly the expected Transaction Center fields" do
      build_transaction(buyer: buyer)
      sign_in(buyer)

      get_mine(role: "buyer")

      json = response.parsed_body["transactions"].first
      expect(json.keys).to contain_exactly(
        "id",
        "listing_id",
        "listing_title",
        "buyer_id",
        "seller_id",
        "status",
        "buyer_confirmed_at",
        "seller_confirmed_at",
        "completed_at",
        "cancelled_at",
        "cancelled_by_id",
        "created_at",
        "updated_at",
        "listing_title_snapshot",
        "price_cents_snapshot",
        "currency_snapshot",
        "snapshot_captured",
        "role",
        "listing_thumbnail_url",
        "buyer",
        "seller",
      )
      expect(json["role"]).to eq("buyer")
    end

    it "reports role=seller for the seller's own transaction rows" do
      build_transaction(seller: seller)
      sign_in(seller)

      get_mine(role: "seller")

      expect(response.parsed_body["transactions"].first["role"]).to eq("seller")
    end

    it "never substitutes the listing's current price/title once a snapshot exists" do
      listing =
        build_listing(title: "Ürün A", price_cents: 10_000, currency: "USD", status: :reserved)
      build_transaction(buyer: buyer, listing: listing)
      listing.update!(title: "Ürün B", price_cents: 15_000)
      sign_in(buyer)

      get_mine(role: "buyer")

      json = response.parsed_body["transactions"].first
      expect(json["listing_title_snapshot"]).to eq("Ürün A")
      expect(json["price_cents_snapshot"]).to eq(10_000)
      expect(json["currency_snapshot"]).to eq("USD")
    end
  end

  describe "repeat purchases on the same listing" do
    it "keeps each transaction's own snapshot independent across repeat purchases of an unlimited listing" do
      listing =
        build_listing(
          inventory_mode: Marketplace::Listing.inventory_modes[:unlimited],
          title: "Ürün A",
          price_cents: 10_000,
          currency: "USD",
        )
      now = Time.current
      first =
        build_transaction(
          buyer: buyer,
          listing: listing,
          status: :completed,
          buyer_confirmed_at: now,
          seller_confirmed_at: now,
          completed_at: now,
        )

      listing.update!(title: "Ürün B", price_cents: 15_000)

      second = build_transaction(buyer: buyer, listing: listing, status: :pending)

      sign_in(buyer)
      get_mine(role: "buyer")

      by_id = response.parsed_body["transactions"].index_by { |t| t["id"] }
      expect(by_id[first.id]["listing_title_snapshot"]).to eq("Ürün A")
      expect(by_id[first.id]["price_cents_snapshot"]).to eq(10_000)
      expect(by_id[second.id]["listing_title_snapshot"]).to eq("Ürün B")
      expect(by_id[second.id]["price_cents_snapshot"]).to eq(15_000)
    end
  end
end
