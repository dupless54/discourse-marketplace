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

    private

    def category_must_be_enabled
      return if category.nil?
      return if category.enabled?

      errors.add(:category, I18n.t("marketplace.errors.category_disabled"))
    end
  end
end

# == Schema Information
#
# Table name: marketplace_listings
#
#  id           :bigint           not null, primary key
#  closed_at    :datetime
#  cooked       :text             not null
#  currency     :string(3)        not null
#  price_cents  :bigint           not null
#  published_at :datetime
#  raw          :text             not null
#  status       :integer          default("draft"), not null
#  title        :string(255)      not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  category_id  :bigint           not null
#  seller_id    :integer          not null
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
