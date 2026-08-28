# frozen_string_literal: true

module Marketplace
  class Favorite < ActiveRecord::Base
    self.table_name = "marketplace_favorites"

    belongs_to :user, class_name: "::User"
    belongs_to :listing, class_name: "Marketplace::Listing"

    # Uniqueness is intentionally enforced by the database index rather than
    # an ActiveRecord uniqueness validation. Favorites::Add uses
    # create_or_find_by!, which relies on the unique index to resolve
    # concurrent/replayed inserts safely and idempotently.
  end
end

# == Schema Information
#
# Table name: marketplace_favorites
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  listing_id :bigint           not null
#  user_id    :integer          not null
#
# Indexes
#
#  idx_marketplace_favorites_listing       (listing_id)
#  idx_marketplace_favorites_user_created  (user_id,created_at,id)
#  idx_marketplace_favorites_user_listing  (user_id,listing_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (listing_id => marketplace_listings.id) ON DELETE => cascade
#
