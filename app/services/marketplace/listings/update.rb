# frozen_string_literal: true

module Marketplace
  class Listings::Update
    include Service::Base

    params do
      attribute :listing_id, :integer
      attribute :title, :string
      attribute :raw, :string
      attribute :category_id, :integer
      attribute :price_cents, :integer
      attribute :currency, :string

      validates :listing_id, presence: true
      validates :title, presence: true
      validates :raw, presence: true
      validates :category_id, presence: true
      validates :price_cents, presence: true, numericality: { only_integer: true }
      validates :currency, presence: true

      before_validation { self.currency = currency.to_s.upcase }
    end

    model :listing
    policy :can_edit_marketplace_listing
    model :category

    transaction do
      model :listing, :assign_listing
      model :listing, :save_listing
    end

    private

    def fetch_listing(params:)
      Marketplace::Listing.find_by(id: params.listing_id)
    end

    def can_edit_marketplace_listing(guardian:, listing:)
      guardian.can_edit_marketplace_listing?(listing)
    end

    def fetch_category(params:)
      Marketplace::Category.find_by(id: params.category_id)
    end

    def assign_listing(listing:, params:, category:)
      listing.assign_attributes(
        title: params.title,
        raw: params.raw,
        cooked: PrettyText.cook(params.raw),
        category_id: category.id,
        price_cents: params.price_cents,
        currency: params.currency,
      )
      listing
    end

    def save_listing(listing:)
      listing.save
      listing
    end
  end
end
