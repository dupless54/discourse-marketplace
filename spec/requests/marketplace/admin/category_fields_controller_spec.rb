# frozen_string_literal: true

describe Marketplace::Admin::CategoryFieldsController do
  fab!(:admin)
  fab!(:user)
  fab!(:category, :marketplace_category)

  before { SiteSetting.marketplace_enabled = true }

  def field_params(overrides = {})
    {
      key: "fuel_type",
      label: "Fuel type",
      type: "select",
      required: true,
      enabled: true,
      position: 2,
      placeholder: "Choose fuel",
      help_text: "Choose the vehicle fuel type",
      choices: [{ value: "petrol", label: "Petrol" }, { value: "diesel", label: "Diesel" }],
    }.merge(overrides)
  end

  describe "POST /marketplace/admin/categories/:category_id/fields" do
    it "allows an admin to create a structured field" do
      sign_in(admin)

      expect do
        post "/marketplace/admin/categories/#{category.id}/fields.json", params: field_params
      end.to change { Marketplace::CategoryFieldDefinition.count }.by(1)

      expect(response.status).to eq(201)
      expect(response.parsed_body["field_definition"]).to include(
        "key" => "fuel_type",
        "label" => "Fuel type",
        "type" => "select",
        "required" => true,
        "enabled" => true,
      )
    end

    it "does not allow a non-admin to create a field" do
      sign_in(user)

      expect do
        post "/marketplace/admin/categories/#{category.id}/fields.json", params: field_params
      end.not_to change { Marketplace::CategoryFieldDefinition.count }
      expect(response.status).to eq(403)
    end

    it "rejects invalid keys, types, duplicate keys, and invalid select choices" do
      sign_in(admin)
      Fabricate(:marketplace_category_field_definition, category: category, key: "existing_key")

      [
        field_params(key: "9unsafe"),
        field_params(key: "bad_type", type: "code", choices: []),
        field_params(key: "existing_key", type: "text", choices: []),
        field_params(key: "empty_select", choices: []),
      ].each do |params|
        post "/marketplace/admin/categories/#{category.id}/fields.json", params: params
        expect(response.status).to eq(422)
      end
    end

    it "returns 404 for a missing category" do
      sign_in(admin)

      post "/marketplace/admin/categories/999999999/fields.json", params: field_params

      expect(response.status).to eq(404)
    end
  end

  describe "PUT /marketplace/admin/categories/:category_id/fields/:id" do
    fab!(:field) do
      Fabricate(
        :marketplace_category_field_definition,
        category: category,
        key: "mileage",
        label: "Mileage",
        field_type: "integer",
        position: 1,
      )
    end

    it "updates mutable metadata, ordering, required, and enabled state" do
      sign_in(admin)

      put "/marketplace/admin/categories/#{category.id}/fields/#{field.id}.json",
          params:
            field_params(
              label: "Odometer",
              type: "integer",
              choices: [],
              position: 5,
              required: true,
              enabled: false,
            )

      expect(response.status).to eq(200), response.parsed_body.inspect
      expect(field.reload).to have_attributes(
        key: "mileage",
        label: "Odometer",
        field_type: "integer",
        position: 5,
        required: true,
        enabled: false,
      )
    end

    it "cannot update a field through another category" do
      sign_in(admin)

      put "/marketplace/admin/categories/#{Fabricate(:marketplace_category).id}/fields/#{field.id}.json",
          params: field_params(type: "integer", choices: [])

      expect(response.status).to eq(404)
      expect(field.reload.label).to eq("Mileage")
    end

    it "does not erase historical values when disabling a field" do
      listing = Fabricate(:marketplace_listing, category: category)
      value =
        Fabricate(
          :marketplace_listing_field_value,
          listing: listing,
          field_definition: field,
          value: "125000",
        )
      sign_in(admin)

      put "/marketplace/admin/categories/#{category.id}/fields/#{field.id}.json",
          params: field_params(type: "integer", choices: [], enabled: false)

      expect(response.status).to eq(200), response.parsed_body.inspect
      expect(value.reload.value).to eq("125000")
    end

    it "does not reinterpret stored values by changing a used field's type" do
      listing = Fabricate(:marketplace_listing, category: category)
      Fabricate(
        :marketplace_listing_field_value,
        listing: listing,
        field_definition: field,
        value: "125000",
      )
      sign_in(admin)

      put "/marketplace/admin/categories/#{category.id}/fields/#{field.id}.json",
          params: field_params(type: "text", choices: [])

      expect(response.status).to eq(422)
      expect(field.reload.field_type).to eq("integer")
    end
  end
end
