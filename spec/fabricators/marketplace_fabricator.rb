# frozen_string_literal: true

Fabricator(:marketplace_category, class_name: "Marketplace::Category") do
  name { sequence(:name) { |i| "Category #{i}" } }
  slug { sequence(:slug) { |i| "category-#{i}" } }
  position 0
  enabled true
end

Fabricator(
  :marketplace_category_field_definition,
  class_name: "Marketplace::CategoryFieldDefinition",
) do
  category { Fabricate(:marketplace_category) }
  key { sequence(:key) { |i| "field_#{i}" } }
  label { sequence(:label) { |i| "Field #{i}" } }
  field_type "text"
  required false
  enabled true
  position 0
  choices { [] }
end

Fabricator(:marketplace_listing, class_name: "Marketplace::Listing") do
  seller { Fabricate(:user) }
  category { Fabricate(:marketplace_category) }
  title { sequence(:title) { |i| "Listing #{i}" } }
  raw "This is a listing description."
  cooked "<p>This is a listing description.</p>"
  price_cents 1000
  currency "USD"
  status Marketplace::Listing.statuses[:draft]
end

Fabricator(:marketplace_listing_field_value, class_name: "Marketplace::ListingFieldValue") do
  listing { Fabricate(:marketplace_listing) }
  field_definition { |attrs| Fabricate(:marketplace_category_field_definition, category: attrs[:listing].category) }
  value "Value"
end

Fabricator(:marketplace_finite_listing, from: :marketplace_listing) do
  inventory_mode Marketplace::Listing.inventory_modes[:finite]
  stock_quantity 5
end

Fabricator(:marketplace_unlimited_listing, from: :marketplace_listing) do
  inventory_mode Marketplace::Listing.inventory_modes[:unlimited]
end

Fabricator(:marketplace_transaction, class_name: "Marketplace::Transaction") do
  listing do
    Fabricate(
      :marketplace_listing,
      status: Marketplace::Listing.statuses[:reserved],
    )
  end

  buyer { Fabricate(:user) }
  seller { |attrs| attrs[:listing].seller }
  status Marketplace::Transaction.statuses[:pending]
end

Fabricator(:marketplace_favorite, class_name: "Marketplace::Favorite") do
  user { Fabricate(:user) }
  listing { Fabricate(:marketplace_listing) }
end

Fabricator(:marketplace_offer, class_name: "Marketplace::Offer") do
  listing do
    Fabricate(
      :marketplace_listing,
      status: Marketplace::Listing.statuses[:active],
    )
  end
  buyer { Fabricate(:user) }
  seller { |attrs| attrs[:listing].seller }
  proposed_by { |attrs| attrs[:buyer] }
  status Marketplace::Offer.statuses[:pending]
  amount_cents 800
  currency { |attrs| attrs[:listing].currency }
  expires_at { 48.hours.from_now }
end

Fabricator(:marketplace_offer_event, class_name: "Marketplace::OfferEvent") do
  offer { Fabricate(:marketplace_offer) }
  actor { |attrs| attrs[:offer].proposed_by }
  event_type Marketplace::OfferEvent.event_types[:proposed]
  amount_cents { |attrs| attrs[:offer].amount_cents }
  currency { |attrs| attrs[:offer].currency }
end
