# frozen_string_literal: true

describe Marketplace::ListingQuery, "#results" do
  fab!(:category) { Fabricate(:marketplace_category, enabled: true) }

  before { SiteSetting.marketplace_allowed_currencies = "USD|EUR" }

  def query(params = {})
    described_class.new(params: params).results[:records]
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

  def define_field(key:, field_type:, **overrides)
    Fabricate(
      :marketplace_category_field_definition,
      category: category,
      key: key,
      label: key.titleize,
      field_type: field_type,
      required: false,
      **overrides,
    )
  end

  def set_value(listing, definition, value)
    Fabricate(
      :marketplace_listing_field_value,
      listing: listing,
      field_definition: definition,
      value: value,
    )
  end

  it "filters select values using the selected category definition" do
    platform =
      define_field(
        key: "platform",
        field_type: "select",
        choices: [
          { "value" => "steam", "label" => "Steam" },
          { "value" => "epic", "label" => "Epic" },
        ],
      )
    steam = make_listing
    epic = make_listing
    set_value(steam, platform, "steam")
    set_value(epic, platform, "epic")

    records = query(category_id: category.id, field_filters: { platform: "steam" })

    expect(records).to contain_exactly(steam)
  end

  it "filters text case-insensitively and treats LIKE wildcards literally" do
    edition = define_field(key: "edition", field_type: "text")
    matching = make_listing
    unrelated = make_listing
    set_value(matching, edition, "Collector 100% Edition")
    set_value(unrelated, edition, "Collector Edition")

    records = query(category_id: category.id, field_filters: { edition: "collector 100%" })

    expect(records).to contain_exactly(matching)
  end

  it "filters boolean values exactly" do
    warranty = define_field(key: "warranty", field_type: "boolean")
    covered = make_listing
    uncovered = make_listing
    set_value(covered, warranty, "true")
    set_value(uncovered, warranty, "false")

    expect(query(category_id: category.id, field_filters: { warranty: "true" })).to contain_exactly(
      covered,
    )
    expect(query(category_id: category.id, field_filters: { warranty: false })).to contain_exactly(
      uncovered,
    )
  end

  it "supports exact and min/max integer filters, including negative values" do
    score = define_field(key: "score", field_type: "integer")
    low = make_listing
    middle = make_listing
    high = make_listing
    set_value(low, score, "-5")
    set_value(middle, score, "10")
    set_value(high, score, "25")

    expect(query(category_id: category.id, field_filters: { score: "10" })).to contain_exactly(
      middle,
    )
    expect(
      query(category_id: category.id, field_filters: { score: { min: "-5", max: "10" } }),
    ).to contain_exactly(low, middle)
  end

  it "ANDs multiple dynamic filters without duplicating listings" do
    platform =
      define_field(
        key: "platform",
        field_type: "select",
        choices: [
          { "value" => "steam", "label" => "Steam" },
          { "value" => "epic", "label" => "Epic" },
        ],
      )
    warranty = define_field(key: "warranty", field_type: "boolean")
    matching = make_listing
    wrong_platform = make_listing
    wrong_warranty = make_listing

    set_value(matching, platform, "steam")
    set_value(matching, warranty, "true")
    set_value(wrong_platform, platform, "epic")
    set_value(wrong_platform, warranty, "true")
    set_value(wrong_warranty, platform, "steam")
    set_value(wrong_warranty, warranty, "false")

    records =
      query(category_id: category.id, field_filters: { platform: "steam", warranty: "true" })

    expect(records).to contain_exactly(matching)
  end

  it "requires category_id when dynamic filters are supplied" do
    define_field(key: "platform", field_type: "text")

    expect { query(field_filters: { platform: "steam" }) }.to raise_error(
      Discourse::InvalidParameters,
    )
  end

  it "rejects unknown or disabled field keys" do
    disabled = define_field(key: "hidden", field_type: "text", enabled: false)
    expect(disabled).not_to be_enabled

    expect do query(category_id: category.id, field_filters: { unknown: "x" }) end.to raise_error(
      Discourse::InvalidParameters,
    )
    expect do query(category_id: category.id, field_filters: { hidden: "x" }) end.to raise_error(
      Discourse::InvalidParameters,
    )
  end

  it "rejects invalid select, boolean, and integer range values" do
    define_field(
      key: "platform",
      field_type: "select",
      choices: [{ "value" => "steam", "label" => "Steam" }],
    )
    define_field(key: "warranty", field_type: "boolean")
    define_field(key: "score", field_type: "integer")

    expect do
      query(category_id: category.id, field_filters: { platform: "unknown" })
    end.to raise_error(Discourse::InvalidParameters)
    expect do
      query(category_id: category.id, field_filters: { warranty: "maybe" })
    end.to raise_error(Discourse::InvalidParameters)
    expect do
      query(category_id: category.id, field_filters: { score: { min: "20", max: "10" } })
    end.to raise_error(Discourse::InvalidParameters)
  end
end
