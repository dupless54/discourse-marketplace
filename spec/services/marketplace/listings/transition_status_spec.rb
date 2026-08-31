# frozen_string_literal: true

describe Marketplace::Listings::TransitionStatus do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category, :marketplace_category)

  let(:guardian) { seller.guardian }

  def build_listing(status:, **overrides)
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[status],
      **overrides,
    )
  end

  def call_service(guardian:, listing_id:, status:)
    described_class.call(guardian: guardian, params: { listing_id: listing_id, status: status })
  end

  it "transitions draft to active and sets published_at" do
    listing = build_listing(status: :draft)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "active")

    expect(result).to be_success
    expect(result.listing.status).to eq("active")
    expect(result.listing.published_at).to be_present
  end

  it "preserves an existing published_at when transitioning to active" do
    original_time = 2.days.ago
    listing = build_listing(status: :draft, published_at: original_time)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "active")

    expect(result).to be_success
    expect(result.listing.published_at).to be_within(1.second).of(original_time)
  end

  it "transitions active to archived and sets closed_at" do
    listing = build_listing(status: :active)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "archived")

    expect(result).to be_success
    expect(result.listing.status).to eq("archived")
    expect(result.listing.closed_at).to be_present
  end

  it "transitions sold to archived without overwriting an existing closed_at" do
    original_time = 3.days.ago
    listing = build_listing(status: :sold, closed_at: original_time)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "archived")

    expect(result).to be_success
    expect(result.listing.status).to eq("archived")
    expect(result.listing.closed_at).to be_within(1.second).of(original_time)
  end

  it "rejects draft to archived" do
    listing = build_listing(status: :draft)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "archived")

    expect(result).to be_failure
    expect(result).to fail_a_policy(:transition_allowed)
  end

  it "rejects active to sold" do
    listing = build_listing(status: :active)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "sold")

    expect(result).to be_failure
    expect(result).to fail_a_contract
  end

  it "rejects active to reserved" do
    listing = build_listing(status: :active)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "reserved")

    expect(result).to be_failure
    expect(result).to fail_a_contract
  end

  it "rejects reserved to sold" do
    listing = build_listing(status: :reserved)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "sold")

    expect(result).to be_failure
    expect(result).to fail_a_contract
  end

  it "rejects archived to active" do
    listing = build_listing(status: :archived)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "active")

    expect(result).to be_failure
    expect(result).to fail_a_policy(:transition_allowed)
  end

  it "fails policy for a non-owner" do
    non_owner = Fabricate(:user, trust_level: TrustLevel[1])
    listing = build_listing(status: :draft)
    result = call_service(guardian: non_owner.guardian, listing_id: listing.id, status: "active")

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_transition_marketplace_listing_status)
  end

  it "fails policy for a suspended owner" do
    suspended_seller =
      Fabricate(:user, suspended_till: 1.year.from_now, suspended_at: Time.zone.now)
    listing =
      Fabricate(
        :marketplace_listing,
        seller: suspended_seller,
        category: category,
        status: Marketplace::Listing.statuses[:draft],
      )
    result =
      call_service(guardian: suspended_seller.guardian, listing_id: listing.id, status: "active")

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_transition_marketplace_listing_status)
  end

  it "fails policy for a silenced owner" do
    silenced_seller = Fabricate(:user, silenced_till: 1.year.from_now)
    listing =
      Fabricate(
        :marketplace_listing,
        seller: silenced_seller,
        category: category,
        status: Marketplace::Listing.statuses[:draft],
      )
    result =
      call_service(guardian: silenced_seller.guardian, listing_id: listing.id, status: "active")

    expect(result).to be_failure
    expect(result).to fail_a_policy(:can_transition_marketplace_listing_status)
  end

  it "fails with a not found model when the listing does not exist" do
    result = call_service(guardian: guardian, listing_id: -1, status: "active")

    expect(result).to be_failure
    expect(result).to fail_to_find_a_model(:listing)
  end

  it "fails the contract for an unsupported target status" do
    listing = build_listing(status: :draft)
    result = call_service(guardian: guardian, listing_id: listing.id, status: "bogus")

    expect(result).to be_failure
    expect(result).to fail_a_contract
  end

  it "does not allow any transaction-driven transition in its whitelist" do
    expect(described_class::ALLOWED_TRANSITIONS.keys).not_to include("reserved")
    expect(described_class::ALLOWED_TRANSITIONS.values).not_to include("reserved")
    expect(described_class::ALLOWED_TRANSITIONS.values).not_to include("sold")
  end
end
