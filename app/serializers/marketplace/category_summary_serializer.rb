# frozen_string_literal: true

module Marketplace
  class CategorySummarySerializer < ApplicationSerializer
    attributes :id, :name, :slug, :position
  end
end
