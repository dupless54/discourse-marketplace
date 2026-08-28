# frozen_string_literal: true

module Marketplace
  class Listings::Create
    include Service::Base

    params do
      attribute :title, :string
      attribute :raw, :string
      attribute :category_id, :integer
      attribute :price_cents, :integer
      attribute :currency, :string
      attribute :inventory_mode, :string, default: "single"
      attribute :stock_quantity, :integer
      attribute :expires_at, :datetime

      validates :title, presence: true
      validates :raw, presence: true
      validates :category_id, presence: true
      validates :price_cents, presence: true, numericality: { only_integer: true }
      validates :currency, presence: true
      validates :inventory_mode, inclusion: { in: Marketplace::Listing.inventory_modes.keys }
      validates :stock_quantity,
                presence: true,
                numericality: {
                  only_integer: true,
                  greater_than_or_equal_to: 1,
                },
                if: -> { inventory_mode == "finite" }

      before_validation { self.currency = currency.to_s.upcase }
      before_validation { self.inventory_mode = inventory_mode.presence || "single" }
    end

    policy :can_create_marketplace_listing

    model :category

    transaction do
      model :listing, :build_listing
      model :listing, :save_listing
    end

    private

    def can_create_marketplace_listing(guardian:)
      guardian.can_create_marketplace_listing?
    end

    def fetch_category(params:)
      Marketplace::Category.find_by(id: params.category_id)
    end

    def build_listing(guardian:, params:, category:)
      Marketplace::Listing.new(
        seller_id: guardian.user.id,
        title: params.title,
        raw: params.raw,
        cooked: PrettyText.cook(params.raw),
        category_id: category.id,
        price_cents: params.price_cents,
        currency: params.currency,
        status: Marketplace::Listing.statuses[:draft],
        inventory_mode: Marketplace::Listing.inventory_modes[params.inventory_mode],
        stock_quantity: params.inventory_mode == "finite" ? params.stock_quantity : nil,
        expires_at: params.expires_at,
      )
    end

    def save_listing(listing:)
      listing.save
      listing
    end
  end
end
