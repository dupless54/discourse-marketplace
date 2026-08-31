# frozen_string_literal: true

module Marketplace
  class Listing < ActiveRecord::Base
    self.table_name = "marketplace_listings"

    belongs_to :seller, class_name: "::User"
    belongs_to :category, class_name: "Marketplace::Category"
    has_many :field_values,
             class_name: "Marketplace::ListingFieldValue",
             inverse_of: :listing,
             dependent: :destroy

    MAX_TEXT_LENGTH = 255
    MAX_TEXTAREA_LENGTH = 5000
    INTEGER_RANGE = (-(2**63))..((2**63) - 1)

    enum :status, { draft: 0, active: 10, reserved: 20, sold: 30, archived: 40 }, scopes: false
    enum :inventory_mode, { single: 0, finite: 10, unlimited: 20 }, scopes: false

    validates :title, presence: true, length: { in: 3..255 }
    validates :raw, presence: true
    validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency,
              presence: true,
              format: {
                with: /\A[A-Z]{3}\z/,
              },
              inclusion: {
                in: ->(_) { SiteSetting.marketplace_allowed_currencies.split("|") },
              }
    validates :stock_quantity,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 1,
              },
              if: -> { finite? }
    validates :stock_quantity, absence: true, unless: -> { finite? }
    validates :stock_reserved, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :stock_sold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :category_must_be_enabled, if: -> { new_record? || will_save_change_to_category_id? }
    validate :stock_reserved_and_sold_within_quantity, if: -> { finite? }
    validate :inventory_mode_immutable_after_transactions,
             if: -> { persisted? && will_save_change_to_inventory_mode? }
    validate :structured_field_values_are_valid

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
    # .cook (below), already done by Listings::Create/Update. This hook
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

    # Listings/Create and Listings/Update both cook `raw` through this
    # rather than calling PrettyText.cook directly, so every listing's
    # embedded images are clickable to a lightbox/zoom view.
    #
    # Core only wraps an image in the lightbox markup
    # (CookedProcessorMixin#add_lightbox!) as part of CookedPostProcessor,
    # which is a background pass tied to a real Post/Topic (needs
    # post.topic_id, post.should_secure_uploads?, post.post_analyzer, ...)
    # that a Marketplace listing has no equivalent of and has no safe way to
    # fabricate. So this reproduces only the minimal, verified structural
    # subset PhotoSwipe's client-side discourse/lib/lightbox actually reads
    # -- `div.lightbox-wrapper > a.lightbox[href] > img`, built with the same
    # add_next_sibling/add_child moves add_lightbox! itself uses -- and skips
    # the Post-specific extras (secure-uploads variants, the filename/size
    # meta overlay, the download link): those degrade gracefully when absent
    # (see initLightbox's optional chaining / `if (!href) hide` handling),
    # so omitting them is a smaller surface, not a broken one.
    def self.cook(raw)
      cooked = PrettyText.cook(raw)
      fragment = Nokogiri::HTML5.fragment(cooked)

      fragment
        .css("img")
        .each do |img|
          next if img.ancestors("a").any?
          next if img["class"].to_s.split(" ").include?("emoji")

          src = img["src"]
          next if src.blank?

          wrapper = Nokogiri::XML::Node.new("div", fragment)
          wrapper["class"] = "lightbox-wrapper"
          img.add_next_sibling(wrapper)
          wrapper.add_child(img)

          link = Nokogiri::XML::Node.new("a", fragment)
          link["class"] = "lightbox"
          link["href"] = src
          img.add_next_sibling(link)
          link.add_child(img)
        end

      fragment.to_html
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

      @thumbnail_url =
        begin
          image = Nokogiri::HTML5.fragment(cooked).at_css("img:not(.emoji):not(.avatar)")
          image&.attr("src").presence
        end
    end

    def validate_structured_field_values(payload, definitions:)
      @structured_field_errors = []
      normalized_payload = normalize_structured_payload(payload)
      return nil if normalized_payload.nil?

      definitions_by_key = definitions.index_by(&:key)
      unknown_keys = normalized_payload.keys - definitions_by_key.keys
      if unknown_keys.present?
        add_structured_field_error(I18n.t("marketplace.errors.unknown_fields"))
        return nil
      end

      normalized = {}
      definitions.each do |definition|
        raw_value = normalized_payload[definition.key]
        value = normalize_structured_value(definition, raw_value)

        if value.nil?
          if definition.required?
            add_structured_field_error(
              I18n.t("marketplace.errors.required_field", label: definition.label),
            )
          end
          next
        end

        normalized[definition.id] = value
      end

      @structured_field_errors.empty? ? normalized : nil
    end

    def replace_enabled_field_values!(normalized_values, definitions:, category_changed:)
      transaction do
        if category_changed
          field_values.delete_all
        else
          field_values.where(field_definition_id: definitions.map(&:id)).delete_all
        end

        normalized_values.each do |definition_id, value|
          field_values.create!(field_definition_id: definition_id, value: value)
        end
      end
    end

    private

    def normalize_structured_payload(payload)
      payload = payload.to_unsafe_h if payload.respond_to?(:to_unsafe_h)
      if !payload.is_a?(Hash)
        add_structured_field_error(I18n.t("marketplace.errors.malformed_fields"))
        return nil
      end

      payload.each_with_object({}) do |(key, value), normalized|
        if !key.is_a?(String) && !key.is_a?(Symbol)
          add_structured_field_error(I18n.t("marketplace.errors.malformed_fields"))
          next
        end
        if value.is_a?(Hash) || value.is_a?(Array) || value.respond_to?(:to_unsafe_h)
          add_structured_field_error(I18n.t("marketplace.errors.malformed_fields"))
          next
        end

        normalized[key.to_s] = value
      end
    end

    def normalize_structured_value(definition, raw_value)
      return nil if raw_value.nil?

      case definition.field_type
      when "boolean"
        return "true" if raw_value == true || raw_value == "true"
        return "false" if raw_value == false || raw_value == "false"

        add_structured_field_error(
          I18n.t("marketplace.errors.invalid_boolean", label: definition.label),
        )
        nil
      when "integer"
        string = raw_value.to_s.strip
        return nil if string.blank?
        if !string.match?(/\A-?\d+\z/)
          add_structured_field_error(
            I18n.t("marketplace.errors.invalid_integer", label: definition.label),
          )
          return nil
        end

        integer = Integer(string, 10)
        if !INTEGER_RANGE.cover?(integer)
          add_structured_field_error(
            I18n.t("marketplace.errors.invalid_integer", label: definition.label),
          )
          return nil
        end
        integer.to_s
      when "select"
        string = raw_value.to_s
        return nil if string.blank?
        if !definition.choices.any? { |choice| (choice["value"] || choice[:value]) == string }
          add_structured_field_error(
            I18n.t("marketplace.errors.invalid_select", label: definition.label),
          )
          return nil
        end
        string
      when "text", "textarea"
        string = raw_value.to_s.strip
        return nil if string.blank?
        if Nokogiri::HTML5.fragment(string).at_css("*").present?
          add_structured_field_error(
            I18n.t("marketplace.errors.field_html_not_allowed", label: definition.label),
          )
          return nil
        end
        maximum = definition.field_type == "textarea" ? MAX_TEXTAREA_LENGTH : MAX_TEXT_LENGTH
        if string.length > maximum
          add_structured_field_error(
            I18n.t("marketplace.errors.field_too_long", label: definition.label, count: maximum),
          )
          return nil
        end
        string
      end
    end

    def add_structured_field_error(message)
      @structured_field_errors ||= []
      @structured_field_errors << message
    end

    def structured_field_values_are_valid
      Array(@structured_field_errors).each { |message| errors.add(:custom_fields, message) }
    end

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
