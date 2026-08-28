# frozen_string_literal: true

describe Marketplace::Admin::CategoriesController do
  fab!(:admin)
  fab!(:user)

  before { SiteSetting.marketplace_enabled = true }

  describe "GET /marketplace/admin/categories" do
    fab!(:first_category) { Fabricate(:marketplace_category, position: 1, enabled: false) }
    fab!(:second_category) { Fabricate(:marketplace_category, position: 2) }

    it "returns every category in position order to admins" do
      sign_in(admin)

      get "/marketplace/admin/categories.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["categories"]).to eq(
        [
          {
            "id" => first_category.id,
            "name" => first_category.name,
            "slug" => first_category.slug,
            "position" => first_category.position,
            "enabled" => false,
            "field_definitions" => [],
          },
          {
            "id" => second_category.id,
            "name" => second_category.name,
            "slug" => second_category.slug,
            "position" => second_category.position,
            "enabled" => true,
            "field_definitions" => [],
          },
        ],
      )
    end

    it "denies anonymous users" do
      get "/marketplace/admin/categories.json"

      # Marketplace::Admin::CategoriesController < ::Admin::AdminController,
      # which raises Discourse::InvalidAccess (403) for a logged-out request
      # via requires_login/ensure_admin -- this is core's own, unmodified
      # admin-controller behavior, not a Marketplace 404-for-IDOR case.
      expect(response.status).to eq(403)
    end

    it "denies non-admin users" do
      sign_in(user)

      get "/marketplace/admin/categories.json"

      expect(response.status).to eq(403)
    end
  end

  describe "POST /marketplace/admin/categories" do
    let(:params) do
      {
        name: "Electronics",
        slug: "electronics",
        position: 3,
        enabled: true,
      }
    end

    it "creates a category for an admin" do
      sign_in(admin)

      expect do
        post "/marketplace/admin/categories.json", params: params
      end.to change { Marketplace::Category.count }.by(1)

      expect(response.status).to eq(201)
      expect(response.parsed_body["category"]).to include(
        "name" => "Electronics",
        "slug" => "electronics",
        "position" => 3,
        "enabled" => true,
      )
    end

    it "does not let a non-admin create a category" do
      sign_in(user)

      expect do
        post "/marketplace/admin/categories.json", params: params
      end.not_to change { Marketplace::Category.count }

      expect(response.status).to eq(403)
    end

    it "rejects an invalid slug without weakening validation" do
      sign_in(admin)

      post "/marketplace/admin/categories.json", params: params.merge(slug: "Not Valid")

      expect(response.status).to eq(422)
      expect(Marketplace::Category.find_by(name: "Electronics")).to be_nil
    end
  end

  describe "PUT /marketplace/admin/categories/:id" do
    fab!(:category) { Fabricate(:marketplace_category, position: 1) }

    it "updates all mutable category fields for an admin" do
      sign_in(admin)

      put "/marketplace/admin/categories/#{category.id}.json",
          params: {
            name: "Home and Garden",
            slug: "home-and-garden",
            position: 5,
            enabled: false,
          }

      expect(response.status).to eq(200)
      expect(category.reload).to have_attributes(
        name: "Home and Garden",
        slug: "home-and-garden",
        position: 5,
        enabled: false,
      )
      expect(response.parsed_body["category"]["enabled"]).to eq(false)
    end

    it "does not let a non-admin update a category" do
      sign_in(user)

      put "/marketplace/admin/categories/#{category.id}.json",
          params: {
            name: "Changed",
            slug: "changed",
            position: 0,
            enabled: false,
          }

      expect(response.status).to eq(403)
      expect(category.reload.name).not_to eq("Changed")
    end

    it "returns 404 for an unknown category" do
      sign_in(admin)

      put "/marketplace/admin/categories/999999.json",
          params: {
            name: "Missing",
            slug: "missing",
            position: 0,
            enabled: true,
          }

      expect(response.status).to eq(404)
    end
  end
end
