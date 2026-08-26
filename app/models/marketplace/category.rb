# frozen_string_literal: true

module Marketplace
  class Category < ActiveRecord::Base
    self.table_name = "marketplace_categories"

    SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

    validates :name, presence: true, length: { maximum: 100 }
    validates :slug,
              presence: true,
              uniqueness: true,
              length: {
                maximum: 100,
              },
              format: {
                with: SLUG_FORMAT,
              }

    scope :browsable, -> { where(enabled: true).order(:position) }
  end
end
