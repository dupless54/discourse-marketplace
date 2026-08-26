# frozen_string_literal: true

Fabricator(:marketplace_category, class_name: "Marketplace::Category") do
  sequence(:name) { |i| "Category #{i}" }
  sequence(:slug) { |i| "category-#{i}" }
  position 0
  enabled true
end

Fabricator(:marketplace_listing, class_name: "Marketplace::Listing") do
  seller { Fabricate(:user) }
  category { Fabricate(:marketplace_category) }
  sequence(:title) { |i| "Listing #{i}" }
  raw "This is a listing description."
  cooked "<p>This is a listing description.</p>"
  price_cents 1000
  currency "USD"
  status Marketplace::Listing.statuses[:draft]
end
