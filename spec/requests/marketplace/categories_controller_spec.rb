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

    expect(categories.first.keys).to contain_exactly("id", "name", "slug", "position")
    expect(categories.first).to eq(
      "id" => enabled_category.id,
      "name" => enabled_category.name,
      "slug" => enabled_category.slug,
      "position" => enabled_category.position,
    )
  end

  it "works for anonymous users" do
    get "/marketplace/categories.json"

    expect(response.status).to eq(200)
  end
end
