# frozen_string_literal: true

module Marketplace
  class ListingDetailSerializer < Marketplace::ListingSerializer
    attributes :raw, :cooked, :can_edit, :custom_fields

    def can_edit
      scope.can_edit_marketplace_listing?(object)
    end

    def include_raw?
      can_edit
    end

    def custom_fields
      Marketplace::ListingFieldValue
        .joins(:field_definition)
        .where(
          listing_id: object.id,
          marketplace_category_field_definitions: {
            category_id: object.category_id,
          },
        )
        .order(
          "marketplace_category_field_definitions.position ASC",
          "marketplace_category_field_definitions.id ASC",
        )
        .pluck(
          "marketplace_category_field_definitions.key",
          "marketplace_category_field_definitions.label",
          "marketplace_category_field_definitions.field_type",
          "marketplace_category_field_definitions.choices",
          :value,
        )
        .map do |key, label, type, choices, value|
          display_value =
            if type == "select"
              choices.find { |choice| choice["value"] == value }&.fetch("label", nil) || value
            else
              value
            end

          { key: key, label: label, type: type, value: value, display_value: display_value }
        end
    end
  end
end
