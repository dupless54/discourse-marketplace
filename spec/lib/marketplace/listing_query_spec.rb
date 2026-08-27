# frozen_string_literal: true

describe Marketplace::ListingQuery do
  fab!(:category) { Fabricate(:marketplace_category, enabled: true) }

  before { SiteSetting.marketplace_allowed_currencies = "USD|EUR" }

  def query(params = {})
    described_class.new(params: params).results
  end

  def make_listing(overrides = {})
    Fabricate(
      :marketplace_listing,
      category: category,
      status: Marketplace::Listing.statuses[:active],
      published_at: Time.zone.now,
      **overrides,
    )
  end

  describe "base visibility" do
    it "returns active listings" do
      listing = make_listing
      expect(query[:records]).to include(listing)
    end

    it "hides draft listings" do
      listing = make_listing(status: Marketplace::Listing.statuses[:draft], published_at: nil)
      expect(query[:records]).not_to include(listing)
    end

    it "hides reserved listings" do
      listing = make_listing(status: Marketplace::Listing.statuses[:reserved])
      expect(query[:records]).not_to include(listing)
    end

    it "hides sold listings" do
      listing = make_listing(status: Marketplace::Listing.statuses[:sold])
      expect(query[:records]).not_to include(listing)
    end

    it "hides archived listings" do
      listing = make_listing(status: Marketplace::Listing.statuses[:archived])
      expect(query[:records]).not_to include(listing)
    end

    it "hides active listings whose marketplace category is disabled" do
      listing = make_listing
      listing.category.update!(enabled: false)

      expect(query[:records]).not_to include(listing)
    end
  end

  describe "filters" do
    it "filters by category_id" do
      other_category = Fabricate(:marketplace_category, enabled: true)
      matching = make_listing(category: category)
      other = make_listing(category: other_category)

      records = query(category_id: category.id)[:records]

      expect(records).to include(matching)
      expect(records).not_to include(other)
    end

    it "normalizes currency case-insensitively via uppercase" do
      listing = make_listing(currency: "USD")

      records = query(currency: "usd")[:records]

      expect(records).to include(listing)
    end

    it "raises Discourse::InvalidParameters for an invalid currency" do
      expect { query(currency: "XXX") }.to raise_error(Discourse::InvalidParameters)
    end

    it "filters by min_price_cents" do
      cheap = make_listing(price_cents: 100)
      expensive = make_listing(price_cents: 900)

      records = query(min_price_cents: 500)[:records]

      expect(records).to include(expensive)
      expect(records).not_to include(cheap)
    end

    it "filters by max_price_cents" do
      cheap = make_listing(price_cents: 100)
      expensive = make_listing(price_cents: 900)

      records = query(max_price_cents: 500)[:records]

      expect(records).to include(cheap)
      expect(records).not_to include(expensive)
    end

    it "raises Discourse::InvalidParameters when min_price_cents > max_price_cents" do
      expect { query(min_price_cents: 900, max_price_cents: 100) }.to raise_error(
        Discourse::InvalidParameters,
      )
    end
  end

  describe "strict numeric validation" do
    it "raises for an invalid category_id such as 'abc'" do
      expect { query(category_id: "abc") }.to raise_error(Discourse::InvalidParameters)
    end

    it "raises for category_id 0" do
      expect { query(category_id: 0) }.to raise_error(Discourse::InvalidParameters)
    end

    it "raises for an invalid min_price_cents such as 'abc'" do
      expect { query(min_price_cents: "abc") }.to raise_error(Discourse::InvalidParameters)
    end

    it "raises for a negative min_price_cents" do
      expect { query(min_price_cents: -1) }.to raise_error(Discourse::InvalidParameters)
    end

    it "raises for a leading-zero min_price_cents such as '007'" do
      expect { query(min_price_cents: "007") }.to raise_error(Discourse::InvalidParameters)
    end

    it "raises for an invalid max_price_cents" do
      expect { query(max_price_cents: "abc") }.to raise_error(Discourse::InvalidParameters)
    end

    it "raises for page 0, negative, or non-numeric" do
      expect { query(page: 0) }.to raise_error(Discourse::InvalidParameters)
      expect { query(page: -1) }.to raise_error(Discourse::InvalidParameters)
      expect { query(page: "abc") }.to raise_error(Discourse::InvalidParameters)
    end

    it "raises for per_page 0, negative, or non-numeric" do
      expect { query(per_page: 0) }.to raise_error(Discourse::InvalidParameters)
      expect { query(per_page: -1) }.to raise_error(Discourse::InvalidParameters)
      expect { query(per_page: "abc") }.to raise_error(Discourse::InvalidParameters)
    end
  end

  describe "sorting" do
    it "sorts newest by published_at DESC with id as a deterministic tiebreaker" do
      older = make_listing(published_at: 2.days.ago)
      newer = make_listing(published_at: 1.day.ago)
      same_time_first = make_listing(published_at: newer.published_at)

      records = query(sort: "newest")[:records]

      expect(records.map(&:id)).to eq(
        [same_time_first, newer, older].sort_by { |l| [-l.published_at.to_i, -l.id] }.map(&:id),
      )
    end

    it "sorts price_asc with lowest price first" do
      cheap = make_listing(price_cents: 100)
      mid = make_listing(price_cents: 500)
      expensive = make_listing(price_cents: 900)

      records = query(sort: "price_asc")[:records]

      expect(records.map(&:id)).to eq([cheap, mid, expensive].map(&:id))
    end

    it "sorts price_desc with highest price first" do
      cheap = make_listing(price_cents: 100)
      mid = make_listing(price_cents: 500)
      expensive = make_listing(price_cents: 900)

      records = query(sort: "price_desc")[:records]

      expect(records.map(&:id)).to eq([expensive, mid, cheap].map(&:id))
    end

    it "raises Discourse::InvalidParameters for an unsupported sort" do
      expect { query(sort: "cheapest") }.to raise_error(Discourse::InvalidParameters)
    end
  end

  describe "pagination" do
    it "defaults page to 1" do
      expect(query[:page]).to eq(1)
    end

    it "defaults per_page to 20" do
      expect(query[:per_page]).to eq(20)
    end

    it "clamps per_page above 50 to 50" do
      expect(query(per_page: 500)[:per_page]).to eq(50)
    end

    it "applies the page offset correctly" do
      listings = Array.new(5) { |i| make_listing(published_at: (10 - i).days.ago) }

      page_one = query(per_page: 2, page: 1)[:records]
      page_two = query(per_page: 2, page: 2)[:records]

      expect(page_one.map(&:id)).to eq(listings.first(2).map(&:id))
      expect(page_two.map(&:id)).to eq(listings[2, 2].map(&:id))
    end

    it "has_more is true when another page exists" do
      Array.new(3) { make_listing }

      expect(query(per_page: 2, page: 1)[:has_more]).to eq(true)
    end

    it "has_more is false on the last page" do
      Array.new(3) { make_listing }

      expect(query(per_page: 2, page: 2)[:has_more]).to eq(false)
    end
  end

  describe "search" do
    it "matches on title" do
      listing = make_listing(title: "Vintage Synthesizer")
      other = make_listing(title: "Something else entirely")

      records = query(q: "synthesizer")[:records]

      expect(records).to include(listing)
      expect(records).not_to include(other)
    end

    it "matches on raw description" do
      listing = make_listing(title: "Ordinary title", raw: "Rare vintage synthesizer inside")
      other = make_listing(title: "Ordinary title", raw: "Nothing special here")

      records = query(q: "synthesizer")[:records]

      expect(records).to include(listing)
      expect(records).not_to include(other)
    end

    it "escapes LIKE wildcard input so '%' is treated literally" do
      listing = make_listing(title: "100% Cotton", raw: "Details here")
      unrelated = make_listing(title: "Totally unrelated title", raw: "Different details")

      records = query(q: "100%")[:records]

      expect(records).to include(listing)
      expect(records).not_to include(unrelated)
    end
  end

  describe "result contract" do
    it "returns exactly records, page, per_page, and has_more" do
      make_listing

      expect(query.keys).to contain_exactly(:records, :page, :per_page, :has_more)
    end
  end
end
