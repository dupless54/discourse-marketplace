# frozen_string_literal: true

Fabricator(:marketplace_category, class_name: "Marketplace::Category") do
  sequence(:name) { |i| "Category #{i}" }
  sequence(:slug) { |i| "category-#{i}" }
  position 0
  enabled true
end
