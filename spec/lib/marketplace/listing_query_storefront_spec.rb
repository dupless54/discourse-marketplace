# frozen_string_literal: true

RSpec.describe Marketplace::ListingQuery do
  fab!(:seller, :user)
  fab!(:other_seller, :user)
  fab!(:category, :marketplace_category)

  def active_listing(user:, title:)
    Fabricate(
      :marketplace_listing,
      seller: user,
      category: category,
      title: title,
      status: Marketplace::Listing.statuses[:active],
      published_at: Time.current,
    )
  end

  it "can be internally scoped to one seller without weakening browse visibility" do
    own = active_listing(user: seller, title: "Own")
    active_listing(user: other_seller, title: "Other")
    Fabricate(:marketplace_listing, seller: seller, category: category, title: "Draft")

    result = described_class.new(params: {}, seller_id: seller.id).results

    expect(result[:records].map(&:id)).to eq([own.id])
  end

  it "does not accept seller_id as a public query param" do
    own = active_listing(user: seller, title: "Own")
    other = active_listing(user: other_seller, title: "Other")

    result = described_class.new(params: { seller_id: seller.id }).results

    expect(result[:records].map(&:id)).to contain_exactly(own.id, other.id)
  end
end
