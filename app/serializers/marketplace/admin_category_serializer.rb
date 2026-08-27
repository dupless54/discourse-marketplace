# frozen_string_literal: true

module Marketplace
  class AdminCategorySerializer < ApplicationSerializer
    attributes :id, :name, :slug, :position, :enabled
  end
end
