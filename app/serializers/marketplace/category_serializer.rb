# frozen_string_literal: true

module Marketplace
  class CategorySerializer < ApplicationSerializer
    attributes :id, :name, :slug, :position, :field_definitions

    def field_definitions
      object.field_definitions.select(&:enabled?).map(&:public_schema)
    end
  end
end
