# frozen_string_literal: true

module Marketplace
  class CategorySerializer < ApplicationSerializer
    attributes :id, :name, :slug, :position
  end
end
