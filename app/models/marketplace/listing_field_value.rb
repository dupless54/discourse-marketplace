# frozen_string_literal: true

module Marketplace
  class ListingFieldValue < ActiveRecord::Base
    self.table_name = "marketplace_listing_field_values"

    belongs_to :listing, class_name: "Marketplace::Listing", inverse_of: :field_values
    belongs_to :field_definition,
               class_name: "Marketplace::CategoryFieldDefinition",
               inverse_of: :listing_field_values

    validates :field_definition_id, uniqueness: { scope: :listing_id }
    validates :value, presence: true
    validate :definition_matches_listing_category

    private

    def definition_matches_listing_category
      return if listing.blank? || field_definition.blank?
      return if listing.category_id == field_definition.category_id

      errors.add(:field_definition, I18n.t("marketplace.errors.field_wrong_category"))
    end
  end
end

# == Schema Information
#
# Table name: marketplace_listing_field_values
#
#  id                  :bigint           not null, primary key
#  value               :text             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  field_definition_id :bigint           not null
#  listing_id          :bigint           not null
#
# Indexes
#
#  idx_marketplace_listing_field_values_definition  (field_definition_id)
#  idx_marketplace_listing_field_values_unique      (listing_id,field_definition_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (field_definition_id => marketplace_category_field_definitions.id) ON DELETE => restrict
#  fk_rails_...  (listing_id => marketplace_listings.id) ON DELETE => cascade
#
