# frozen_string_literal: true

describe Marketplace::ListingFieldValue do
  fab!(:listing, :marketplace_listing)

  it "rejects a definition from another category" do
    other_definition = Fabricate(:marketplace_category_field_definition)
    value =
      Fabricate.build(
        :marketplace_listing_field_value,
        listing: listing,
        field_definition: other_definition,
      )

    expect(value).not_to be_valid
    expect(value.errors[:field_definition]).to be_present
  end

  it "allows only one value per definition and listing" do
    definition = Fabricate(:marketplace_category_field_definition, category: listing.category)
    Fabricate(:marketplace_listing_field_value, listing: listing, field_definition: definition)

    duplicate =
      Fabricate.build(
        :marketplace_listing_field_value,
        listing: listing,
        field_definition: definition,
      )
    expect(duplicate).not_to be_valid
  end
end
