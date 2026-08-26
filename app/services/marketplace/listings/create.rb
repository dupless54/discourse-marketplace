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

      validates :title, presence: true
      validates :raw, presence: true
      validates :category_id, presence: true
      validates :price_cents, presence: true, numericality: { only_integer: true }
      validates :currency, presence: true

      before_validation { self.currency = currency.to_s.upcase }
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
      )
    end

    def save_listing(listing:)
      listing.save
      listing
    end
  end
end
