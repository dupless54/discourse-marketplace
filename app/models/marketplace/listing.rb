# frozen_string_literal: true

module Marketplace
  class Listing < ActiveRecord::Base
    self.table_name = "marketplace_listings"

    belongs_to :seller, class_name: "::User"
    belongs_to :category, class_name: "Marketplace::Category"

    enum :status, { draft: 0, active: 10, reserved: 20, sold: 30, archived: 40 }, scopes: false

    validates :title, presence: true, length: { in: 3..255 }
    validates :raw, presence: true
    validates :price_cents,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
              }
    validates :currency,
              presence: true,
              format: {
                with: /\A[A-Z]{3}\z/,
              },
              inclusion: {
                in: -> (_) { SiteSetting.marketplace_allowed_currencies.split("|") },
              }
    validate :category_must_be_enabled, if: -> { new_record? || will_save_change_to_category_id? }

    private

    def category_must_be_enabled
      return if category.nil?
      return if category.enabled?

      errors.add(:category, I18n.t("marketplace.errors.category_disabled"))
    end
  end
end
