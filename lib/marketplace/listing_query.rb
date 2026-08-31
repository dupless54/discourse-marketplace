# frozen_string_literal: true

module Marketplace
  class ListingQuery
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 50
    SORTS = %w[newest price_asc price_desc].freeze
    MAX_STRUCTURED_FILTERS = 30

    def initialize(params: {}, seller_id: nil)
      @params = params
      @seller_id = seller_id
    end

    def results
      scope = base_scope
      scope = filter_by_seller(scope)
      scope = filter_by_category(scope)
      scope = filter_by_structured_fields(scope)
      scope = filter_by_currency(scope)
      scope = filter_by_price(scope)
      scope = filter_by_query(scope)
      scope = apply_sort(scope)

      per_page = fetch_per_page
      page = fetch_page

      records = scope.limit(per_page + 1).offset((page - 1) * per_page).to_a
      has_more = records.size > per_page
      records = records.first(per_page)

      { records: records, page: page, per_page: per_page, has_more: has_more }
    end

    private

    attr_reader :params, :seller_id

    # Mandatory, no exceptions: browse/index only ever returns active listings
    # in enabled categories, regardless of who is asking. No guardian is even
    # accepted here, so there is no code path that could branch into a bypass.
    def base_scope
      Marketplace::Listing
        .includes(:seller, :category)
        .joins(:category)
        .where(marketplace_listings: { status: Marketplace::Listing.statuses[:active] })
        .where(marketplace_categories: { enabled: true })
        .where(
          "marketplace_listings.expires_at IS NULL OR marketplace_listings.expires_at > ?",
          Time.current,
        )
        .where(
          "marketplace_listings.inventory_mode <> :finite OR (" \
            "marketplace_listings.stock_quantity IS NOT NULL AND " \
            "marketplace_listings.stock_reserved + marketplace_listings.stock_sold < " \
            "marketplace_listings.stock_quantity)",
          finite: Marketplace::Listing.inventory_modes[:finite],
        )
    end

    def filter_by_seller(scope)
      return scope if seller_id.nil?

      scope.where(seller_id: seller_id)
    end

    def filter_by_category(scope)
      return scope if selected_category_id.nil?

      scope.where(category_id: selected_category_id)
    end

    def filter_by_structured_fields(scope)
      raw_filters = params[:field_filters]
      return scope if raw_filters.blank?
      raise Discourse::InvalidParameters.new(:field_filters) if selected_category_id.nil?

      filters = normalize_structured_filters(raw_filters)
      return scope if filters.empty?
      if filters.length > MAX_STRUCTURED_FILTERS
        raise Discourse::InvalidParameters.new(:field_filters)
      end

      definitions =
        Marketplace::CategoryFieldDefinition
          .enabled
          .where(category_id: selected_category_id, key: filters.keys)
          .index_by(&:key)

      raise Discourse::InvalidParameters.new(:field_filters) if definitions.length != filters.length

      filters.each do |key, raw_value|
        scope = apply_structured_filter(scope, definitions.fetch(key), raw_value)
      end

      scope
    end

    def filter_by_currency(scope)
      return scope if params[:currency].blank?

      currency = params[:currency].to_s.upcase
      allowed = SiteSetting.marketplace_allowed_currencies.split("|")
      raise Discourse::InvalidParameters.new(:currency) if !allowed.include?(currency)

      scope.where(currency: currency)
    end

    def filter_by_price(scope)
      min =
        (
          if params[:min_price_cents].present?
            non_negative_integer(params[:min_price_cents], :min_price_cents)
          end
        )
      max =
        (
          if params[:max_price_cents].present?
            non_negative_integer(params[:max_price_cents], :max_price_cents)
          end
        )

      raise Discourse::InvalidParameters.new(:min_price_cents) if min && max && min > max

      scope = scope.where("marketplace_listings.price_cents >= ?", min) if min
      scope = scope.where("marketplace_listings.price_cents <= ?", max) if max
      scope
    end

    def filter_by_query(scope)
      return scope if params[:q].blank?

      term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s)}%"
      scope.where(
        "marketplace_listings.title ILIKE :term OR marketplace_listings.raw ILIKE :term",
        term: term,
      )
    end

    def apply_sort(scope)
      sort = params[:sort].presence || "newest"
      raise Discourse::InvalidParameters.new(:sort) if !SORTS.include?(sort)

      case sort
      when "price_asc"
        scope.order(price_cents: :asc, id: :desc)
      when "price_desc"
        scope.order(price_cents: :desc, id: :desc)
      else
        scope.order(published_at: :desc, id: :desc)
      end
    end

    def selected_category_id
      return @selected_category_id if defined?(@selected_category_id)

      @selected_category_id =
        if params[:category_id].blank?
          nil
        else
          positive_integer(params[:category_id], :category_id)
        end
    end

    def normalize_structured_filters(raw_filters)
      raw_filters = raw_filters.to_unsafe_h if raw_filters.respond_to?(:to_unsafe_h)
      raise Discourse::InvalidParameters.new(:field_filters) if !raw_filters.is_a?(Hash)

      raw_filters.each_with_object({}) do |(raw_key, raw_value), normalized|
        key = raw_key.to_s
        if !key.match?(Marketplace::CategoryFieldDefinition::KEY_FORMAT)
          raise Discourse::InvalidParameters.new(:field_filters)
        end

        normalized[key] = raw_value
      end
    end

    def apply_structured_filter(scope, definition, raw_value)
      case definition.field_type
      when "integer"
        apply_integer_structured_filter(scope, definition, raw_value)
      when "boolean"
        apply_boolean_structured_filter(scope, definition, raw_value)
      when "select"
        apply_select_structured_filter(scope, definition, raw_value)
      when "text", "textarea"
        apply_text_structured_filter(scope, definition, raw_value)
      else
        raise Discourse::InvalidParameters.new(:field_filters)
      end
    end

    def apply_text_structured_filter(scope, definition, raw_value)
      value = scalar_structured_filter(raw_value).strip
      return scope if value.blank?

      maximum =
        (
          if definition.field_type == "textarea"
            Marketplace::Listing::MAX_TEXTAREA_LENGTH
          else
            Marketplace::Listing::MAX_TEXT_LENGTH
          end
        )
      raise Discourse::InvalidParameters.new(:field_filters) if value.length > maximum

      term = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
      matching_ids =
        Marketplace::ListingFieldValue
          .where(field_definition_id: definition.id)
          .where("marketplace_listing_field_values.value ILIKE ?", term)
          .select(:listing_id)

      scope.where(id: matching_ids)
    end

    def apply_select_structured_filter(scope, definition, raw_value)
      value = scalar_structured_filter(raw_value)
      return scope if value.blank?

      allowed_values = definition.choices.map { |choice| choice["value"] || choice[:value] }
      raise Discourse::InvalidParameters.new(:field_filters) if !allowed_values.include?(value)

      scope.where(id: exact_structured_value_ids(definition, value))
    end

    def apply_boolean_structured_filter(scope, definition, raw_value)
      value =
        case raw_value
        when true, "true"
          "true"
        when false, "false"
          "false"
        when nil, ""
          return scope
        else
          raise Discourse::InvalidParameters.new(:field_filters)
        end

      scope.where(id: exact_structured_value_ids(definition, value))
    end

    def apply_integer_structured_filter(scope, definition, raw_value)
      range = parameter_hash(raw_value)
      if range.nil?
        value = signed_integer(raw_value, :field_filters, allow_blank: true)
        return scope if value.nil?

        return scope.where(id: exact_structured_value_ids(definition, value.to_s))
      end

      normalized_range = range.transform_keys(&:to_s)
      if (normalized_range.keys - %w[min max]).present?
        raise Discourse::InvalidParameters.new(:field_filters)
      end

      min = signed_integer(normalized_range["min"], :field_filters, allow_blank: true)
      max = signed_integer(normalized_range["max"], :field_filters, allow_blank: true)
      return scope if min.nil? && max.nil?
      raise Discourse::InvalidParameters.new(:field_filters) if min && max && min > max

      numeric_value =
        "CASE WHEN marketplace_listing_field_values.value ~ '^-{0,1}[0-9]+$' " \
          "THEN marketplace_listing_field_values.value::numeric END"
      matching_values = Marketplace::ListingFieldValue.where(field_definition_id: definition.id)
      matching_values = matching_values.where("#{numeric_value} >= ?", min) if min
      matching_values = matching_values.where("#{numeric_value} <= ?", max) if max

      scope.where(id: matching_values.select(:listing_id))
    end

    def exact_structured_value_ids(definition, value)
      Marketplace::ListingFieldValue.where(field_definition_id: definition.id, value: value).select(
        :listing_id,
      )
    end

    def scalar_structured_filter(value)
      if value.is_a?(Hash) || value.is_a?(Array) || value.respond_to?(:to_unsafe_h)
        raise Discourse::InvalidParameters.new(:field_filters)
      end

      value.to_s
    end

    def parameter_hash(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      value.is_a?(Hash) ? value : nil
    end

    def fetch_page
      return 1 if params[:page].blank?

      positive_integer(params[:page], :page)
    end

    def fetch_per_page
      return DEFAULT_PER_PAGE if params[:per_page].blank?

      [positive_integer(params[:per_page], :per_page), MAX_PER_PAGE].min
    end

    # Strict: only digit strings are accepted. "abc", "1.5", "-1", "" all raise
    # rather than silently coercing to 0 via to_i.
    def positive_integer(value, key)
      str = value.to_s.strip
      raise Discourse::InvalidParameters.new(key) if !str.match?(/\A[1-9]\d*\z/)

      str.to_i
    end

    def non_negative_integer(value, key)
      str = value.to_s.strip
      raise Discourse::InvalidParameters.new(key) if !str.match?(/\A(?:0|[1-9]\d*)\z/)

      str.to_i
    end

    def signed_integer(value, key, allow_blank: false)
      str = value.to_s.strip
      return nil if allow_blank && str.blank?
      raise Discourse::InvalidParameters.new(key) if !str.match?(/\A-?\d+\z/)

      integer = Integer(str, 10)
      if !Marketplace::Listing::INTEGER_RANGE.cover?(integer)
        raise Discourse::InvalidParameters.new(key)
      end

      integer
    end
  end
end
