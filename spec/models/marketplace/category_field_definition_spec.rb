# frozen_string_literal: true

describe Marketplace::CategoryFieldDefinition do
  fab!(:category) { Fabricate(:marketplace_category) }

  def build_field(overrides = {})
    Fabricate.build(
      :marketplace_category_field_definition,
      { category: category, key: "mileage", label: "Mileage" }.merge(overrides),
    )
  end

  it "requires a safe machine key that is unique within its category" do
    Fabricate(:marketplace_category_field_definition, category: category, key: "mileage")

    expect(build_field).not_to be_valid
    expect(build_field(key: "Not safe!")).not_to be_valid
    expect(build_field(key: "model_year")).to be_valid
  end

  it "allows the same key in another category" do
    Fabricate(:marketplace_category_field_definition, category: category, key: "platform")

    other = build_field(category: Fabricate(:marketplace_category), key: "platform")
    expect(other).to be_valid
  end

  it "accepts only the supported field types" do
    expect(build_field(field_type: "integer")).to be_valid
    expect(build_field(field_type: "ruby")).not_to be_valid
  end

  it "requires bounded, stable select choices" do
    select =
      build_field(
        field_type: "select",
        choices: [{ "value" => "diesel", "label" => "Diesel" }],
      )
    expect(select).to be_valid

    expect(build_field(field_type: "select", choices: [])).not_to be_valid
    expect(
      build_field(
        field_type: "select",
        choices: [{ "value" => "diesel", "label" => "Diesel", "html" => "<b>x</b>" }],
      ),
    ).not_to be_valid
  end

  it "orders definitions deterministically" do
    second = Fabricate(:marketplace_category_field_definition, category: category, position: 2)
    first = Fabricate(:marketplace_category_field_definition, category: category, position: 1)

    expect(category.field_definitions.reload).to eq([first, second])
  end

  it "never permits the machine key to be changed after creation" do
    field = Fabricate(:marketplace_category_field_definition, category: category, key: "mileage")

    expect(field.update(key: "distance")).to eq(false)
    expect(field.errors[:key]).to be_present
  end

  it "keeps the type and stable select values once listings use them" do
    field =
      Fabricate(
        :marketplace_category_field_definition,
        category: category,
        key: "fuel",
        field_type: "select",
        choices: [{ "value" => "diesel", "label" => "Diesel" }],
      )
    listing = Fabricate(:marketplace_listing, category: category)
    Fabricate(
      :marketplace_listing_field_value,
      listing: listing,
      field_definition: field,
      value: "diesel",
    )

    expect(field.update(field_type: "text", choices: [])).to eq(false)
    field.reload
    expect(
      field.update(choices: [{ "value" => "electric", "label" => "Electric" }]),
    ).to eq(false)
    expect(
      field.update(choices: [{ "value" => "diesel", "label" => "Dizel" }]),
    ).to eq(true)
  end

  it "limits the number of fields in one category" do
    stub_const("Marketplace::CategoryFieldDefinition::MAX_FIELDS_PER_CATEGORY", 1)
    Fabricate(:marketplace_category_field_definition, category: category)

    expect(build_field(key: "another")).not_to be_valid
  end
end
