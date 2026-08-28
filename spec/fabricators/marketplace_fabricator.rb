# frozen_string_literal: true

Fabricator(:marketplace_category, class_name: "Marketplace::Category") do
  name { sequence(:name) { |i| "Category #{i}" } }
  slug { sequence(:slug) { |i| "category-#{i}" } }
  position 0
  enabled true
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
