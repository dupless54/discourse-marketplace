# frozen_string_literal: true

module Marketplace
  class Listing < ActiveRecord::Base
    self.table_name = "marketplace_listings"

    belongs_to :seller, class_name: "::User"
    belongs_to :category, class_name: "Marketplace::Category"

    enum :status, { draft: 0, active: 10, reserved: 20, sold: 30, archived: 40 }, scopes: false
    enum :inventory_mode, { single: 0, finite: 10, unlimited: 20 }, scopes: false

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
    validates :stock_quantity,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 1,
              },
              if: -> { finite? }
    validates :stock_quantity, absence: true, unless: -> { finite? }
    validates :stock_reserved,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
              }
    validates :stock_sold,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 0,
              }
    validate :category_must_be_enabled, if: -> { new_record? || will_save_change_to_category_id? }
    validate :stock_reserved_and_sold_within_quantity, if: -> { finite? }
    validate :inventory_mode_immutable_after_transactions,
             if: -> { persisted? && will_save_change_to_inventory_mode? }

    # Purely time-derived -- an expired listing is never destroyed or
    # status-transitioned automatically, so this stays a live computation
    # rather than a persisted flag (see #purchasable?).
    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # Only meaningful for finite listings; nil for single/unlimited, which
    # have no fixed capacity to report a remaining count against.
    def stock_available
      return nil if !finite?

      [stock_quantity.to_i - stock_reserved.to_i - stock_sold.to_i, 0].max
    end

    # The single source of truth for "can a new transaction be opened on
    # this listing right now" -- status alone is not enough once finite
    # listings stay "active" for their whole purchasable lifetime (see
    # docs/MARKETPLACE_ARCHITECTURE.md). Guardian and the transaction
    # services both key off this rather than re-deriving it.
    def purchasable?
      return false if !active?
      return false if expired?
      return true if !finite?

      stock_available.to_i > 0
    end

    # Images/attachments use the standard Discourse mechanism: they are
    # embedded in `raw` markdown (the same `upload://<short-url>` syntax the
    # composer inserts everywhere else) and rendered into `cooked` by
    # PrettyText.cook, already done by Listings::Create/Update. This hook
    # only does the housekeeping every other Discourse model with
    # user-suppliable upload references does (see e.g. core's Draft#save,
    # Badge#save): associate any uploads newly referenced in `raw` so they
    # survive the upload cleanup job, and drop the association for any that
    # are no longer referenced after an edit.
    after_save do
      if saved_change_to_raw?
        UploadReference.ensure_exist!(upload_ids: Upload.extract_upload_ids(raw), target: self)
      end
    end

    # Card thumbnail, derived from the already-persisted `cooked` column --
    # no extra query, no migration. Mirrors the same safe, precedented
    # technique core itself uses to read structure out of cooked HTML
    # (Nokogiri::HTML5.fragment(cooked), see e.g. Post#mentions): parse the
    # fragment and pull the `src` off the first non-emoji <img>, exactly the
    # thumbnail-sized image Discourse's own upload pipeline already wrote
    # into `cooked` when the raw markdown referenced an upload. Never
    # returns markup, only a URL string. A listing with no image (a plain
    # description, or a non-image attachment like a PDF) simply has no <img>
    # to match, so this returns nil and the client falls back to a
    # placeholder -- generic attachments are untouched either way.
    def thumbnail_url
      return @thumbnail_url if defined?(@thumbnail_url)

      @thumbnail_url = begin
        image = Nokogiri::HTML5.fragment(cooked).at_css("img:not(.emoji):not(.avatar)")
        image&.attr("src").presence
      end
    end

    private

    def category_must_be_enabled
      return if category.nil?
      return if category.enabled?

      errors.add(:category, I18n.t("marketplace.errors.category_disabled"))
    end

    def stock_reserved_and_sold_within_quantity
      return if stock_quantity.blank?
      return if stock_reserved.to_i + stock_sold.to_i <= stock_quantity

      errors.add(:stock_quantity, I18n.t("marketplace.errors.stock_exceeded"))
    end

    # Switching inventory_mode after a listing has any transaction history
    # (even a cancelled one) would strand or misinterpret stock_reserved/
    # stock_sold, which only mean something relative to a single mode's own
    # semantics -- see docs/MARKETPLACE_ARCHITECTURE.md.
    def inventory_mode_immutable_after_transactions
      return if Marketplace::Transaction.where(listing_id: id).none?

      errors.add(:inventory_mode, I18n.t("marketplace.errors.inventory_mode_locked"))
    end
  end
end

# == Schema Information
#
# Table name: marketplace_listings
#
#  id             :bigint           not null, primary key
#  closed_at      :datetime
#  cooked         :text             not null
#  currency       :string(3)        not null
#  expires_at     :datetime
#  inventory_mode :integer          default("single"), not null
#  price_cents    :bigint           not null
#  published_at   :datetime
#  raw            :text             not null
#  status         :integer          default("draft"), not null
#  stock_quantity :bigint
#  stock_reserved :bigint           default(0), not null
#  stock_sold     :bigint           default(0), not null
#  title          :string(255)      not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  category_id    :bigint           not null
#  seller_id      :integer          not null
#
# Indexes
#
#  idx_marketplace_listings_browse_status_published  (status,published_at,id)
#  idx_on_seller_id_status_created_at_410eb7684b     (seller_id,status,created_at)
#  idx_on_status_category_id_created_at_8352d3dd6b   (status,category_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (category_id => marketplace_categories.id) ON DELETE => restrict
#
