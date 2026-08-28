# frozen_string_literal: true

describe Marketplace::ListingsController do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category) { Fabricate(:marketplace_category) }

  before do
    SiteSetting.marketplace_enabled = true
    SiteSetting.marketplace_allowed_currencies = "USD|EUR"
  end

  def json_body
    response.parsed_body.values.first
  end

  def create_params(overrides = {})
    {
      title: "A great listing",
      raw: "Details here",
      category_id: category.id,
      price_cents: 500,
      currency: "usd",
    }.merge(overrides)
  end

  describe "#create" do
    it "creates a draft listing owned by the current user" do
      sign_in(seller)
      post "/marketplace/listings.json", params: create_params

      expect(response.status).to eq(201)
      expect(json_body["status"]).to eq("draft")
      expect(json_body["currency"]).to eq("USD")
      expect(Marketplace::Listing.last.seller_id).to eq(seller.id)
    end

    it "rejects anonymous create" do
      post "/marketplace/listings.json", params: create_params

      expect(response.status).to eq(403)
    end

    it "returns 404 when the category does not exist" do
      sign_in(seller)
      post "/marketplace/listings.json", params: create_params(category_id: -1)

      expect(response.status).to eq(404)
    end

    it "returns 400 when required params are missing" do
      sign_in(seller)
      post "/marketplace/listings.json", params: create_params.except(:title)

      expect(response.status).to eq(400)
    end

    it "returns 422 when the category is disabled" do
      sign_in(seller)
      disabled_category = Fabricate(:marketplace_category, enabled: false)
      post "/marketplace/listings.json", params: create_params(category_id: disabled_category.id)

      expect(response.status).to eq(422)
    end

    it "ignores a client-supplied seller_id and status" do
      sign_in(seller)
      other_user = Fabricate(:user)
      post "/marketplace/listings.json", params: create_params(seller_id: other_user.id, status: 30)

      expect(response.status).to eq(201)
      listing = Marketplace::Listing.last
      expect(listing.seller_id).to eq(seller.id)
      expect(listing.status).to eq("draft")
    end

    it "creates a finite listing with the given stock_quantity" do
      sign_in(seller)
      post "/marketplace/listings.json",
           params: create_params(inventory_mode: "finite", stock_quantity: 4)

      expect(response.status).to eq(201)
      expect(json_body["inventory_mode"]).to eq("finite")
      expect(json_body["stock_quantity"]).to eq(4)
      expect(json_body["stock_available"]).to eq(4)
    end

    it "creates an unlimited listing" do
      sign_in(seller)
      post "/marketplace/listings.json", params: create_params(inventory_mode: "unlimited")

      expect(response.status).to eq(201)
      expect(json_body["inventory_mode"]).to eq("unlimited")
      expect(json_body["stock_quantity"]).to be_nil
    end

    it "returns 400 for finite with no stock_quantity" do
      sign_in(seller)
      post "/marketplace/listings.json", params: create_params(inventory_mode: "finite")

      expect(response.status).to eq(400)
    end
  end

  describe "#show" do
    it "allows the owner to view their own draft" do
      listing = Fabricate(:marketplace_listing, seller: seller, category: category)
      sign_in(seller)
      get "/marketplace/listings/#{listing.id}.json"

      expect(response.status).to eq(200)
    end

    it "returns 404 when another user views a draft" do
      listing = Fabricate(:marketplace_listing, seller: seller, category: category)
      sign_in(Fabricate(:user))
      get "/marketplace/listings/#{listing.id}.json"

      expect(response.status).to eq(404)
    end

    it "returns 404 when an anonymous user views a draft" do
      listing = Fabricate(:marketplace_listing, seller: seller, category: category)
      get "/marketplace/listings/#{listing.id}.json"

      expect(response.status).to eq(404)
    end

    it "allows anyone to view an active listing, with cooked but no raw for an ordinary viewer" do
      listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
        )
      get "/marketplace/listings/#{listing.id}.json"

      expect(response.status).to eq(200)
      expect(json_body["cooked"]).to be_present
      expect(json_body).not_to have_key("raw")
    end

    it "includes raw for the owner viewing their own listing" do
      listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
        )
      sign_in(seller)
      get "/marketplace/listings/#{listing.id}.json"

      expect(response.status).to eq(200)
      expect(json_body["raw"]).to be_present
    end

    it "returns 404 for a missing listing" do
      get "/marketplace/listings/-1.json"

      expect(response.status).to eq(404)
    end

    it "serializes the seller as a basic user without private fields" do
      listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
        )
      get "/marketplace/listings/#{listing.id}.json"

      seller_json = json_body["seller"]
      expect(seller_json["id"]).to eq(seller.id)
      expect(seller_json["username"]).to eq(seller.username)
      expect(seller_json).not_to have_key("email")
    end

    it "serves the SPA shell, not JSON, for direct/HTML navigation (no .json suffix, Accept: text/html)" do
      listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
        )

      get "/marketplace/listings/#{listing.id}", headers: { "Accept" => "text/html" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
      expect(response.body).not_to include(listing.title)
    end

    it "serves the SPA shell for a missing/private listing under HTML navigation, without touching the DB" do
      other_seller = Fabricate(:user)
      draft = Fabricate(:marketplace_listing, seller: other_seller, category: category)

      get "/marketplace/listings/#{draft.id}", headers: { "Accept" => "text/html" }
      expect(response.status).to eq(200)

      get "/marketplace/listings/999999999", headers: { "Accept" => "text/html" }
      expect(response.status).to eq(200)
    end

    it "still serves real listing JSON for an unsuffixed path when Accept is application/json, matching ajax()" do
      listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
        )

      get "/marketplace/listings/#{listing.id}", headers: { "Accept" => "application/json" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("application/json")
      expect(json_body["id"]).to eq(listing.id)
      expect(json_body["title"]).to eq(listing.title)
    end
  end

  describe "SPA direct-navigation shell (F5 / direct URL, no client-side Ember router yet)" do
    it "returns 200 HTML for the bare /marketplace root" do
      get "/marketplace", headers: { "Accept" => "text/html" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end

    it "returns 200 HTML for /marketplace/new" do
      get "/marketplace/new", headers: { "Accept" => "text/html" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end

    it "returns 200 HTML for /marketplace/mine" do
      get "/marketplace/mine", headers: { "Accept" => "text/html" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end

    it "returns 200 HTML for /marketplace/listings/:id/edit regardless of whether the listing exists" do
      get "/marketplace/listings/999999999/edit", headers: { "Accept" => "text/html" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end

    it "leaves the listings JSON index API at /marketplace/listings completely unrouted to the shell" do
      get "/marketplace/listings.json"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to have_key("pagination")
    end
  end

  describe "#update" do
    let(:listing) do
      Fabricate(:marketplace_listing, seller: seller, category: category, title: "Original title")
    end

    it "allows the owner to update their own draft listing" do
      sign_in(seller)
      put "/marketplace/listings/#{listing.id}.json",
          params: create_params(title: "Updated title")

      expect(response.status).to eq(200)
      expect(json_body["title"]).to eq("Updated title")
    end

    it "returns 404 when a non-owner updates the listing" do
      sign_in(Fabricate(:user, trust_level: TrustLevel[1]))
      put "/marketplace/listings/#{listing.id}.json", params: create_params

      expect(response.status).to eq(404)
    end

    it "returns 404 for a missing listing" do
      sign_in(seller)
      put "/marketplace/listings/-1.json", params: create_params

      expect(response.status).to eq(404)
    end

    it "returns 404 when the category does not exist" do
      sign_in(seller)
      put "/marketplace/listings/#{listing.id}.json", params: create_params(category_id: -1)

      expect(response.status).to eq(404)
    end

    it "returns 422 on validation failure" do
      sign_in(seller)
      put "/marketplace/listings/#{listing.id}.json", params: create_params(title: "ab")

      expect(response.status).to eq(422)
    end

    it "switches a fresh listing to finite with a stock_quantity" do
      sign_in(seller)
      put "/marketplace/listings/#{listing.id}.json",
          params: create_params(inventory_mode: "finite", stock_quantity: 3)

      expect(response.status).to eq(200)
      expect(json_body["inventory_mode"]).to eq("finite")
      expect(json_body["stock_quantity"]).to eq(3)
    end

    it "returns 422 when shrinking stock_quantity below already-committed stock" do
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
      sign_in(seller)
      put "/marketplace/listings/#{finite_listing.id}.json",
          params: create_params(inventory_mode: "finite", stock_quantity: 3)

      expect(response.status).to eq(422)
    end
  end

  describe "#update_status" do
    it "allows the owner to transition draft to active" do
      listing = Fabricate(:marketplace_listing, seller: seller, category: category)
      sign_in(seller)
      put "/marketplace/listings/#{listing.id}/status.json", params: { status: "active" }

      expect(response.status).to eq(200)
      expect(json_body["status"]).to eq("active")
    end

    it "returns 422 for an invalid transition such as draft to archived" do
      listing = Fabricate(:marketplace_listing, seller: seller, category: category)
      sign_in(seller)
      put "/marketplace/listings/#{listing.id}/status.json", params: { status: "archived" }

      expect(response.status).to eq(422)
    end

    it "returns 404 when a non-owner changes the status" do
      listing = Fabricate(:marketplace_listing, seller: seller, category: category)
      sign_in(Fabricate(:user, trust_level: TrustLevel[1]))
      put "/marketplace/listings/#{listing.id}/status.json", params: { status: "active" }

      expect(response.status).to eq(404)
    end

    it "returns 400 for an unsupported target status such as sold or reserved" do
      listing = Fabricate(:marketplace_listing, seller: seller, category: category)
      sign_in(seller)
      put "/marketplace/listings/#{listing.id}/status.json", params: { status: "sold" }

      expect(response.status).to eq(400)
    end

    it "returns 404 for a missing listing" do
      sign_in(seller)
      put "/marketplace/listings/-1/status.json", params: { status: "active" }

      expect(response.status).to eq(404)
    end
  end

  describe "#transaction" do
    fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
    fab!(:unrelated_user) { Fabricate(:user, trust_level: TrustLevel[1]) }

    def build_listing(status: :reserved, **overrides)
      Fabricate(
        :marketplace_listing,
        seller: seller,
        category: category,
        status: Marketplace::Listing.statuses[status],
        **overrides,
      )
    end

    it "returns the current user's open transaction on the listing" do
      listing = build_listing
      transaction =
        Fabricate(:marketplace_transaction, listing: listing, buyer: buyer, seller: seller)
      sign_in(buyer)

      get "/marketplace/listings/#{listing.id}/transaction.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["transaction"]["id"]).to eq(transaction.id)
    end

    it "works the same for the seller side of the same transaction" do
      listing = build_listing
      transaction =
        Fabricate(:marketplace_transaction, listing: listing, buyer: buyer, seller: seller)
      sign_in(seller)

      get "/marketplace/listings/#{listing.id}/transaction.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["transaction"]["id"]).to eq(transaction.id)
    end

    it "returns 404 when the current user has no transaction on the listing" do
      listing = build_listing
      sign_in(buyer)

      get "/marketplace/listings/#{listing.id}/transaction.json"

      expect(response.status).to eq(404)
    end

    it "returns 404 for a cancelled transaction so a new purchase can start" do
      listing = build_listing(status: :active)
      Fabricate(
        :marketplace_transaction,
        listing: listing,
        buyer: buyer,
        seller: seller,
        status: Marketplace::Transaction.statuses[:cancelled],
        cancelled_at: Time.current,
        cancelled_by_id: buyer.id,
      )
      sign_in(buyer)

      get "/marketplace/listings/#{listing.id}/transaction.json"

      expect(response.status).to eq(404)
    end

    it "never returns another user's transaction on the same listing (non-enumerable)" do
      listing = build_listing
      Fabricate(:marketplace_transaction, listing: listing, buyer: buyer, seller: seller)
      sign_in(unrelated_user)

      get "/marketplace/listings/#{listing.id}/transaction.json"

      expect(response.status).to eq(404)
    end

    it "rejects anonymous access" do
      listing = build_listing
      Fabricate(:marketplace_transaction, listing: listing, buyer: buyer, seller: seller)

      get "/marketplace/listings/#{listing.id}/transaction.json"

      expect(response.status).to eq(403)
    end

    it "returns 404 for a missing listing" do
      sign_in(buyer)

      get "/marketplace/listings/-1/transaction.json"

      expect(response.status).to eq(404)
    end
  end

  describe "#mine" do
    def get_mine(params = {})
      get "/marketplace/listings/mine.json", params: params
    end

    def listing_ids
      response.parsed_body["listings"].map { |l| l["id"] }
    end

    it "rejects anonymous access" do
      get_mine

      expect(response.status).to eq(403)
    end

    it "returns the current user's own listings across every status" do
      draft = Fabricate(:marketplace_listing, seller: seller, category: category)
      active =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
        )
      reserved =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:reserved],
        )
      sold =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:sold],
        )
      archived =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:archived],
        )
      sign_in(seller)

      get_mine

      expect(listing_ids).to contain_exactly(
        draft.id,
        active.id,
        reserved.id,
        sold.id,
        archived.id,
      )
    end

    it "never returns another seller's listings (non-enumerable)" do
      other_seller = Fabricate(:user, trust_level: TrustLevel[1])
      mine = Fabricate(:marketplace_listing, seller: seller, category: category)
      Fabricate(:marketplace_listing, seller: other_seller, category: category)
      sign_in(seller)

      get_mine

      expect(listing_ids).to eq([mine.id])
    end

    it "returns page, per_page, and has_more reflecting the request" do
      Array.new(3) { Fabricate(:marketplace_listing, seller: seller, category: category) }
      sign_in(seller)

      get_mine(page: 1, per_page: 2)

      pagination = response.parsed_body["pagination"]
      expect(pagination["page"]).to eq(1)
      expect(pagination["per_page"]).to eq(2)
      expect(pagination["has_more"]).to eq(true)
      expect(response.parsed_body["listings"].size).to eq(2)
    end

    it "clamps per_page above 50 to 50" do
      Fabricate(:marketplace_listing, seller: seller, category: category)
      sign_in(seller)

      get_mine(per_page: 500)

      expect(response.parsed_body["pagination"]["per_page"]).to eq(50)
    end

    it "returns 400 for invalid page/per_page" do
      sign_in(seller)

      get_mine(page: 0)
      expect(response.status).to eq(400)

      get_mine(per_page: -1)
      expect(response.status).to eq(400)

      get_mine(page: "abc")
      expect(response.status).to eq(400)
    end

    it "exposes stock, mode, expiry, and status for the seller's own finite listing" do
      finite_listing =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
          inventory_mode: Marketplace::Listing.inventory_modes[:finite],
          stock_quantity: 5,
          stock_reserved: 1,
          stock_sold: 2,
          expires_at: 1.week.from_now,
        )
      sign_in(seller)

      get_mine

      listing_json = response.parsed_body["listings"].first
      expect(listing_json["id"]).to eq(finite_listing.id)
      expect(listing_json["inventory_mode"]).to eq("finite")
      expect(listing_json["stock_quantity"]).to eq(5)
      expect(listing_json["stock_available"]).to eq(2)
      expect(listing_json["stock_sold"]).to eq(2)
      expect(listing_json["status"]).to eq("active")
      expect(listing_json["expires_at"]).to be_present
    end
  end
end
