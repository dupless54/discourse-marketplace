# frozen_string_literal: true

describe Marketplace::Listing do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category, :marketplace_category)

  before { SiteSetting.marketplace_allowed_currencies = "USD|EUR" }

  def definition(key, type, **attributes)
    choices = type == "select" ? [{ "value" => "diesel", "label" => "Diesel" }] : []
    Fabricate(
      :marketplace_category_field_definition,
      category: category,
      key: key,
      label: key.humanize,
      field_type: type,
      choices: choices,
      **attributes,
    )
  end

  def base_params(overrides = {})
    {
      title: "Structured listing",
      raw: "Description",
      category_id: category.id,
      price_cents: 500,
      currency: "USD",
      custom_fields: {
      },
    }.merge(overrides)
  end

  def create_listing(overrides = {})
    Marketplace::Listings::Create.call(guardian: seller.guardian, params: base_params(overrides))
  end

  def update_listing(listing, overrides = {})
    Marketplace::Listings::Update.call(
      guardian: seller.guardian,
      params: base_params({ listing_id: listing.id }.merge(overrides)),
    )
  end

  it "accepts and canonically stores all supported types" do
    definition("name", "text", position: 1)
    definition("notes", "textarea", position: 2)
    definition("mileage", "integer", position: 3)
    definition("trade_available", "boolean", position: 4)
    definition("fuel", "select", position: 5)

    result =
      create_listing(
        custom_fields: {
          name: "  BMW 320d  ",
          notes: "  Clean car  ",
          mileage: "00125000",
          trade_available: false,
          fuel: "diesel",
        },
      )

    expect(result).to be_success
    expect(result.listing.field_values.joins(:field_definition).pluck(:key, :value).to_h).to eq(
      "name" => "BMW 320d",
      "notes" => "Clean car",
      "mileage" => "125000",
      "trade_available" => "false",
      "fuel" => "diesel",
    )
  end

  it "rejects a missing required value" do
    definition("mileage", "integer", required: true)

    result = create_listing

    expect(result).to be_failure
    expect(result.listing.errors[:custom_fields]).to be_present
    expect(Marketplace::Listing.count).to eq(0)
  end

  it "rejects unknown, cross-category, and disabled keys" do
    Fabricate(
      :marketplace_category_field_definition,
      category: Fabricate(:marketplace_category),
      key: "foreign_key",
    )
    definition("disabled_key", "text", enabled: false)

    %w[unknown_key foreign_key disabled_key].each do |key|
      result = create_listing(custom_fields: { key => "value" })
      expect(result).to be_failure
      expect(result.listing.errors[:custom_fields]).to be_present
    end
  end

  it "rejects invalid integer, boolean, and select values" do
    definition("mileage", "integer")
    definition("instant", "boolean")
    definition("fuel", "select")

    [{ mileage: "12.5" }, { instant: "yes" }, { fuel: "electric" }].each do |custom_fields|
      result = create_listing(custom_fields: custom_fields)
      expect(result).to be_failure
      expect(result.listing.errors[:custom_fields]).to be_present
    end
  end

  it "rejects nested or non-object custom field payloads" do
    definition("name", "text")

    [{ name: { html: "<script>alert(1)</script>" } }, %w[name value]].each do |payload|
      result = create_listing(custom_fields: payload)
      expect(result).to be_failure
      expect(result.listing.errors[:custom_fields]).to be_present
    end
  end

  it "rejects HTML even for a known text field" do
    definition("platform", "text")

    result = create_listing(custom_fields: { platform: "<script>alert(1)</script>" })

    expect(result).to be_failure
    expect(result.listing.errors[:custom_fields]).to be_present
  end

  it "omits blank optional values instead of persisting empty rows" do
    definition("platform", "text")

    result = create_listing(custom_fields: { platform: "   " })

    expect(result).to be_success
    expect(result.listing.field_values).to be_empty
  end

  it "updates existing values without duplicating them" do
    definition("mileage", "integer", required: true)
    listing = create_listing(custom_fields: { mileage: 100 }).listing

    result = update_listing(listing, custom_fields: { mileage: 200 })

    expect(result).to be_success
    expect(listing.field_values.reload.pluck(:value)).to eq(["200"])
  end

  it "removes old-category values and never maps same-named fields during category change" do
    definition("platform", "text")
    listing = create_listing(custom_fields: { platform: "Old platform" }).listing
    new_category = Fabricate(:marketplace_category)
    new_definition =
      Fabricate(
        :marketplace_category_field_definition,
        category: new_category,
        key: "platform",
        label: "New platform",
        required: true,
      )

    result =
      update_listing(
        listing,
        category_id: new_category.id,
        custom_fields: {
          platform: "New platform value",
        },
      )

    expect(result).to be_success
    expect(listing.field_values.reload.pluck(:field_definition_id, :value)).to eq(
      [[new_definition.id, "New platform value"]],
    )
  end

  it "requires the new category's required fields before changing category" do
    definition("platform", "text")
    listing = create_listing(custom_fields: { platform: "Old" }).listing
    new_category = Fabricate(:marketplace_category)
    Fabricate(
      :marketplace_category_field_definition,
      category: new_category,
      key: "delivery",
      required: true,
    )

    result = update_listing(listing, category_id: new_category.id, custom_fields: {})

    expect(result).to be_failure
    expect(listing.reload.category_id).to eq(category.id)
    expect(listing.field_values.reload.pluck(:value)).to eq(["Old"])
  end

  it "preserves historical values when a definition is disabled" do
    field = definition("platform", "text")
    listing = create_listing(custom_fields: { platform: "Steam" }).listing
    field.update!(enabled: false)

    result = update_listing(listing, custom_fields: {})

    expect(result).to be_success
    expect(listing.field_values.reload.pluck(:value)).to eq(["Steam"])
  end

  it "keeps old listings without structured values valid" do
    listing = Fabricate(:marketplace_listing, seller: seller, category: category)

    result = update_listing(listing)

    expect(result).to be_success
    expect(listing.field_values).to be_empty
  end
end
