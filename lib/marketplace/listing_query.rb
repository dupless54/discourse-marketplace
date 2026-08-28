# frozen_string_literal: true

module Marketplace
  class ListingQuery
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 50
    SORTS = %w[newest price_asc price_desc].freeze

    def initialize(params: {})
      @params = params
    end

    def results
      scope = base_scope
      scope = filter_by_category(scope)
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

    attr_reader :params

    # Mandatory, no exceptions: browse/index only ever returns active listings
    # in enabled categories, regardless of who is asking. No guardian is even
    # accepted here, so there is no code path that could branch into a bypass.
    def base_scope
      Marketplace::Listing
        .includes(:seller, :category)
        .joins(:category)
        .where(marketplace_listings: { status: Marketplace::Listing.statuses[:active] })
        .where(marketplace_categories: { enabled: true })
        .where("marketplace_listings.expires_at IS NULL OR marketplace_listings.expires_at > ?", Time.current)
        .where(
          "marketplace_listings.inventory_mode <> :finite OR (" \
            "marketplace_listings.stock_quantity IS NOT NULL AND " \
            "marketplace_listings.stock_reserved + marketplace_listings.stock_sold < " \
            "marketplace_listings.stock_quantity)",
          finite: Marketplace::Listing.inventory_modes[:finite],
        )
    end

    def filter_by_category(scope)
      return scope if params[:category_id].blank?

      scope.where(category_id: positive_integer(params[:category_id], :category_id))
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
  end
end
