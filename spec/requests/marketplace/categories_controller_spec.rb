# frozen_string_literal: true

describe Marketplace::CategoriesController do
  fab!(:enabled_category) { Fabricate(:marketplace_category, position: 1) }
  fab!(:disabled_category) { Fabricate(:marketplace_category, position: 0, enabled: false) }

  before { SiteSetting.marketplace_enabled = true }

  it "returns 404 when the plugin is disabled" do
    SiteSetting.marketplace_enabled = false

    get "/marketplace/categories.json"

    expect(response.status).to eq(404)
  end

  it "returns only enabled categories, ordered by position, with the expected keys" do
    get "/marketplace/categories.json"

    expect(response.status).to eq(200)

    categories = response.parsed_body["categories"]
    slugs = categories.map { |c| c["slug"] }

    expect(slugs).to eq([enabled_category.slug])
    expect(slugs).not_to include(disabled_category.slug)

    expect(categories.first.keys).to contain_exactly(
      "id",
      "name",
      "slug",
      "position",
      "field_definitions",
    )
    expect(categories.first).to eq(
      "id" => enabled_category.id,
      "name" => enabled_category.name,
      "slug" => enabled_category.slug,
      "position" => enabled_category.position,
      "field_definitions" => [],
    )
  end

  it "returns only enabled definitions in deterministic order and no admin metadata" do
    later =
      Fabricate(
        :marketplace_category_field_definition,
        category: enabled_category,
        key: "platform",
        label: "Platform",
        position: 2,
      )
    earlier =
      Fabricate(
        :marketplace_category_field_definition,
        category: enabled_category,
        key: "delivery",
        label: "Delivery",
        position: 1,
        required: true,
      )
    Fabricate(
      :marketplace_category_field_definition,
      category: enabled_category,
      enabled: false,
      key: "archived_field",
    )

    get "/marketplace/categories.json"

    fields = response.parsed_body["categories"].first["field_definitions"]
    expect(fields.map { |field| field["key"] }).to eq([earlier.key, later.key])
    expect(fields.first.keys).to contain_exactly(
      "key",
      "label",
      "type",
      "required",
      "position",
      "choices",
      "placeholder",
      "help_text",
    )
    expect(fields.first).not_to have_key("enabled")
    expect(fields.first).not_to have_key("id")
  end

  it "works for anonymous users" do
    get "/marketplace/categories.json"

    expect(response.status).to eq(200)
  end

  it "preloads field definitions instead of querying once per category" do
    3.times do
      category = Fabricate(:marketplace_category)
      Fabricate(:marketplace_category_field_definition, category: category)
    end

    queries = track_sql_queries { get "/marketplace/categories.json" }

    expect(response.status).to eq(200)
    expect(queries.grep(/FROM "marketplace_category_field_definitions"/).length).to eq(1)
  end
end
