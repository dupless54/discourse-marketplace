# frozen_string_literal: true

module Marketplace
  class Category < ActiveRecord::Base
    self.table_name = "marketplace_categories"

    SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

    has_many :field_definitions,
             -> { order(:position, :id) },
             class_name: "Marketplace::CategoryFieldDefinition",
             inverse_of: :category,
             dependent: :destroy

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
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :browsable, -> { where(enabled: true).order(:position) }
  end
end

# == Schema Information
#
# Table name: marketplace_categories
#
#  id         :bigint           not null, primary key
#  enabled    :boolean          default(TRUE), not null
#  name       :string(100)      not null
#  position   :integer          default(0), not null
#  slug       :string(100)      not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_marketplace_categories_on_enabled_and_position  (enabled,position)
#  index_marketplace_categories_on_slug                  (slug) UNIQUE
#
