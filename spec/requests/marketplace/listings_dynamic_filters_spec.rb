# frozen_string_literal: true

describe "GET /marketplace/listings dynamic filters" do
  fab!(:category) { Fabricate(:marketplace_category, enabled: true) }
  fab!(:seller) { Fabricate(:user) }

  before do
    SiteSetting.marketplace_enabled = true
    SiteSetting.marketplace_allowed_currencies = "USD|EUR"
  end

  def make_listing
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[:active],
      published_at: Time.zone.now,
    )
  end

  def listing_ids
    response.parsed_body["listings"].map { |listing| listing["id"] }
  end

  it "passes nested field filters through the public browse endpoint" do
    platform =
      Fabricate(
        :marketplace_category_field_definition,
        category: category,
        key: "platform",
        label: "Platform",
        field_type: "select",
        choices: [
          { "value" => "steam", "label" => "Steam" },
          { "value" => "epic", "label" => "Epic" },
        ],
      )
    mileage =
      Fabricate(
        :marketplace_category_field_definition,
        category: category,
        key: "mileage",
        label: "Mileage",
        field_type: "integer",
      )

    matching = make_listing
    wrong_platform = make_listing
    too_high = make_listing

    Fabricate(
      :marketplace_listing_field_value,
      listing: matching,
      field_definition: platform,
      value: "steam",
    )
    Fabricate(
      :marketplace_listing_field_value,
      listing: matching,
      field_definition: mileage,
      value: "10000",
    )
    Fabricate(
      :marketplace_listing_field_value,
      listing: wrong_platform,
      field_definition: platform,
      value: "epic",
    )
    Fabricate(
      :marketplace_listing_field_value,
      listing: wrong_platform,
      field_definition: mileage,
      value: "10000",
    )
    Fabricate(
      :marketplace_listing_field_value,
      listing: too_high,
      field_definition: platform,
      value: "steam",
    )
    Fabricate(
      :marketplace_listing_field_value,
      listing: too_high,
      field_definition: mileage,
      value: "50000",
    )

    get "/marketplace/listings.json",
        params: {
          category_id: category.id,
          field_filters: {
            platform: "steam",
            mileage: {
              min: "5000",
              max: "20000",
            },
          },
        }

    expect(response.status).to eq(200)
    expect(listing_ids).to eq([matching.id])
  end

  it "returns 400 when a field filter is sent without a category" do
    get "/marketplace/listings.json", params: { field_filters: { platform: "steam" } }

    expect(response.status).to eq(400)
  end
end
