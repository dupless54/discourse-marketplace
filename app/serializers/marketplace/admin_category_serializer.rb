# frozen_string_literal: true

module Marketplace
  class AdminCategorySerializer < ApplicationSerializer
    attributes :id, :name, :slug, :position, :enabled, :field_definitions

    def field_definitions
      object.field_definitions.map do |definition|
        definition.public_schema.merge(id: definition.id, enabled: definition.enabled)
      end
    end
  end
end
