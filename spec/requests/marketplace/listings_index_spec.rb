# frozen_string_literal: true

describe "GET /marketplace/listings" do
  fab!(:category) { Fabricate(:marketplace_category, enabled: true) }
  fab!(:seller) { Fabricate(:user) }

  before do
    SiteSetting.marketplace_enabled = true
    SiteSetting.marketplace_allowed_currencies = "USD|EUR"
  end

  def make_listing(overrides = {})
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[:active],
      published_at: Time.zone.now,
      **overrides,
    )
  end

  def get_listings(params = {})
    get "/marketplace/listings.json", params: params
  end

  def listing_ids
    response.parsed_body["listings"].map { |l| l["id"] }
  end

  describe "anonymous access" do
    it "returns 200 for an anonymous request" do
      make_listing
      get_listings

      expect(response.status).to eq(200)
    end
  end

  describe "top-level response structure" do
    it "has exactly the expected top-level keys" do
      make_listing
      get_listings

      expect(response.parsed_body.keys).to contain_exactly("listings", "pagination")
    end

    it "pagination contains exactly page, per_page, and has_more" do
      make_listing
      get_listings

      expect(response.parsed_body["pagination"].keys).to contain_exactly(
        "page",
        "per_page",
        "has_more",
      )
    end
  end

  describe "status visibility" do
    it "only returns active listings" do
      active = make_listing
      draft = make_listing(status: Marketplace::Listing.statuses[:draft], published_at: nil)
      reserved = make_listing(status: Marketplace::Listing.statuses[:reserved])
      sold = make_listing(status: Marketplace::Listing.statuses[:sold])
      archived = make_listing(status: Marketplace::Listing.statuses[:archived])

      get_listings

      expect(listing_ids).to include(active.id)
      expect(listing_ids).not_to include(draft.id, reserved.id, sold.id, archived.id)
    end

    it "excludes an active listing whose category is disabled" do
      hidden = make_listing
      hidden.category.update!(enabled: false)
      get_listings

      expect(listing_ids).not_to include(hidden.id)
    end

    it "excludes an expired active listing" do
      expired = make_listing(expires_at: 1.hour.ago)
      get_listings

      expect(listing_ids).not_to include(expired.id)
    end

    it "includes an active listing with a future expiration" do
      not_expired = make_listing(expires_at: 1.hour.from_now)
      get_listings

      expect(listing_ids).to include(not_expired.id)
    end

    it "excludes a finite listing with no remaining stock" do
      sold_out =
        make_listing(
          inventory_mode: Marketplace::Listing.inventory_modes[:finite],
          stock_quantity: 2,
          stock_reserved: 1,
          stock_sold: 1,
        )
      get_listings

      expect(listing_ids).not_to include(sold_out.id)
    end

    it "includes a finite listing with remaining stock" do
      in_stock =
        make_listing(
          inventory_mode: Marketplace::Listing.inventory_modes[:finite],
          stock_quantity: 2,
          stock_reserved: 1,
          stock_sold: 0,
        )
      get_listings

      expect(listing_ids).to include(in_stock.id)
    end

    it "includes an unlimited listing regardless of stock_sold" do
      unlimited =
        make_listing(
          inventory_mode: Marketplace::Listing.inventory_modes[:unlimited],
          stock_sold: 40,
        )
      get_listings

      expect(listing_ids).to include(unlimited.id)
    end
  end

  describe "browse serializer fields" do
    it "includes exactly the expected listing fields and a seller object" do
      make_listing
      get_listings

      listing_json = response.parsed_body["listings"].first

      expect(listing_json.keys).to contain_exactly(
        "id",
        "title",
        "category_id",
        "price_cents",
        "currency",
        "status",
        "published_at",
        "thumbnail_url",
        "seller",
        "category",
        "inventory_mode",
        "stock_quantity",
        "stock_available",
        "stock_sold",
        "expires_at",
        "expired",
        "purchasable",
        "favorited",
      )
    end

    it "serializes the category with id, name, slug, and position" do
      make_listing
      get_listings

      category_json = response.parsed_body["listings"].first["category"]

      expect(category_json["id"]).to eq(category.id)
      expect(category_json["name"]).to eq(category.name)
      expect(category_json["slug"]).to eq(category.slug)
    end

    it "never exposes raw, cooked, closed_at, created_at, updated_at, can_edit, or seller_id" do
      make_listing
      get_listings

      listing_json = response.parsed_body["listings"].first

      %w[raw cooked closed_at created_at updated_at can_edit seller_id].each do |field|
        expect(listing_json).not_to have_key(field)
      end
    end

    it "serializes the seller with public BasicUserSerializer fields only" do
      make_listing
      get_listings

      seller_json = response.parsed_body["listings"].first["seller"]

      expect(seller_json["id"]).to eq(seller.id)
      expect(seller_json["username"]).to eq(seller.username)
      expect(seller_json).not_to have_key("email")
    end

    it "returns the first cooked image as thumbnail_url when the listing has one" do
      make_listing(cooked: '<p>Nice</p><img src="/uploads/default/original/1X/photo.png">')
      get_listings

      expect(response.parsed_body["listings"].first["thumbnail_url"]).to eq(
        "/uploads/default/original/1X/photo.png",
      )
    end

    it "returns a null thumbnail_url when the listing has no image" do
      make_listing(cooked: "<p>No photo here.</p>")
      get_listings

      expect(response.parsed_body["listings"].first["thumbnail_url"]).to be_nil
    end
  end

  describe "filter/search query params" do
    it "passes category_id, currency (lowercase), min/max price, and q through to the query" do
      other_category = Fabricate(:marketplace_category, enabled: true)

      matching =
        make_listing(
          category: category,
          currency: "USD",
          price_cents: 500,
          title: "Vintage Synthesizer",
        )
      wrong_category = make_listing(category: other_category, title: "Vintage Synthesizer")
      wrong_currency = make_listing(category: category, currency: "EUR", price_cents: 500)
      wrong_price = make_listing(category: category, currency: "USD", price_cents: 5000)
      wrong_title = make_listing(category: category, currency: "USD", price_cents: 500)

      get_listings(
        category_id: category.id,
        currency: "usd",
        min_price_cents: 100,
        max_price_cents: 1000,
        q: "synthesizer",
      )

      expect(listing_ids).to eq([matching.id])
      expect(listing_ids).not_to include(
        wrong_category.id,
        wrong_currency.id,
        wrong_price.id,
        wrong_title.id,
      )
    end
  end

  describe "sort integration" do
    it "orders by price_asc" do
      cheap = make_listing(price_cents: 100)
      mid = make_listing(price_cents: 500)
      expensive = make_listing(price_cents: 900)

      get_listings(sort: "price_asc")

      expect(listing_ids).to eq([cheap.id, mid.id, expensive.id])
    end

    it "orders by price_desc" do
      cheap = make_listing(price_cents: 100)
      mid = make_listing(price_cents: 500)
      expensive = make_listing(price_cents: 900)

      get_listings(sort: "price_desc")

      expect(listing_ids).to eq([expensive.id, mid.id, cheap.id])
    end
  end

  describe "pagination integration" do
    it "returns page, per_page, and has_more reflecting the request" do
      Array.new(3) { make_listing }

      get_listings(page: 1, per_page: 2)

      pagination = response.parsed_body["pagination"]
      expect(pagination["page"]).to eq(1)
      expect(pagination["per_page"]).to eq(2)
      expect(pagination["has_more"]).to eq(true)
      expect(response.parsed_body["listings"].size).to eq(2)
    end

    it "clamps per_page above 50 to 50" do
      make_listing

      get_listings(per_page: 500)

      expect(response.parsed_body["pagination"]["per_page"]).to eq(50)
    end
  end

  describe "invalid query params" do
    it "returns 400 for an invalid category_id" do
      get_listings(category_id: "abc")
      expect(response.status).to eq(400)
    end

    it "returns 400 for an invalid price filter" do
      get_listings(min_price_cents: "abc")
      expect(response.status).to eq(400)
    end

    it "returns 400 for min_price_cents greater than max_price_cents" do
      get_listings(min_price_cents: 900, max_price_cents: 100)
      expect(response.status).to eq(400)
    end

    it "returns 400 for an invalid sort" do
      get_listings(sort: "cheapest")
      expect(response.status).to eq(400)
    end

    it "returns 400 for an invalid currency" do
      get_listings(currency: "XXX")
      expect(response.status).to eq(400)
    end

    it "returns 400 for invalid page/per_page" do
      get_listings(page: 0)
      expect(response.status).to eq(400)

      get_listings(per_page: -1)
      expect(response.status).to eq(400)

      get_listings(page: "abc")
      expect(response.status).to eq(400)
    end
  end
end
