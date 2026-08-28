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
      attribute :inventory_mode, :string, default: "single"
      attribute :stock_quantity, :integer
      attribute :expires_at, :datetime
      attribute :custom_fields, default: {}

      validates :listing_id, presence: true
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

    model :listing
    policy :can_edit_marketplace_listing
    model :category

    transaction do
      model :listing, :assign_listing
      model :listing, :save_listing
      step :save_field_values
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

    # inventory_mode/stock_quantity are always assigned from params. A
    # seller who isn't changing the sale type simply resubmits the current
    # value, which is a no-op save. An attempted mode switch after the
    # listing has any transaction history is rejected by the model's own
    # inventory_mode_immutable_after_transactions validation and surfaces
    # as an ordinary 422 via on_model_errors(:listing) -- the same path
    # every other listing validation failure already takes. Shrinking
    # stock_quantity below already-committed stock is likewise caught by
    # the model's stock_reserved_and_sold_within_quantity validation.
    def assign_listing(listing:, params:, category:)
      category_changed = listing.category_id != category.id
      listing.assign_attributes(
        title: params.title,
        raw: params.raw,
        cooked: Marketplace::Listing.cook(params.raw),
        category_id: category.id,
        price_cents: params.price_cents,
        currency: params.currency,
        inventory_mode: Marketplace::Listing.inventory_modes[params.inventory_mode],
        stock_quantity: params.inventory_mode == "finite" ? params.stock_quantity : nil,
        expires_at: params.expires_at,
      )

      definitions = category.field_definitions.enabled.ordered.to_a
      normalized_values = listing.validate_structured_field_values(params.custom_fields, definitions: definitions)
      context[:category_changed] = category_changed
      context[:field_definitions] = definitions
      context[:normalized_field_values] = normalized_values || {}
      listing
    end

    def save_listing(listing:)
      listing.save
      listing
    end

    def save_field_values(
      listing:,
      field_definitions:,
      normalized_field_values:,
      category_changed:
    )
      listing.replace_enabled_field_values!(
        normalized_field_values,
        definitions: field_definitions,
        category_changed: category_changed,
      )
    end
  end
end
