# frozen_string_literal: true

module Marketplace
  class FavoritesController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME
    requires_login

    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 50

    def index
      respond_to do |format|
        format.html { render "default/empty" }
        format.json { render_favorites }
      end
    end

    def create
      Marketplace::Favorites::Add.call(
        service_params.deep_merge(params: { listing_id: params[:listing_id] }),
      ) do
        on_success { render_json_dump(favorited: true) }
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_failed_contract do |contract|
          render(
            json: failed_json.merge(errors: contract.errors.full_messages),
            status: :bad_request,
          )
        end
        on_model_not_found(:listing) { raise Discourse::NotFound }
        on_failed_policy(:visible) { raise Discourse::NotFound }
      end
    end

    def destroy
      Marketplace::Favorites::Remove.call(
        service_params.deep_merge(params: { listing_id: params[:listing_id] }),
      ) do
        on_success { render_json_dump(favorited: false) }
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_failed_contract do |contract|
          render(
            json: failed_json.merge(errors: contract.errors.full_messages),
            status: :bad_request,
          )
        end
      end
    end

    private

    def render_favorites
      page = positive_integer_param(params[:page], :page, default: 1)
      per_page = [positive_integer_param(params[:per_page], :per_page, default: DEFAULT_PER_PAGE), MAX_PER_PAGE].min

      scope =
        Marketplace::Favorite
          .where(user_id: current_user.id)
          .joins(listing: :category)
          .includes(listing: %i[seller category])

      if !guardian.is_staff?
        scope =
          scope.where(
            <<~SQL.squish,
              marketplace_listings.seller_id = :user_id
              OR (
                marketplace_listings.status <> :draft
                AND marketplace_categories.enabled = TRUE
              )
            SQL
            user_id: current_user.id,
            draft: Marketplace::Listing.statuses[:draft],
          )
      end

      favorites =
        scope
          .order(created_at: :desc, id: :desc)
          .limit(per_page + 1)
          .offset((page - 1) * per_page)
          .to_a
      has_more = favorites.size > per_page
      favorites = favorites.first(per_page)
      listings = favorites.map(&:listing)
      listings.each { |listing| listing.instance_variable_set(:@marketplace_favorited_by_viewer, true) }

      render_json_dump(
        listings: serialize_data(listings, Marketplace::ListingBrowseSerializer),
        pagination: { page: page, per_page: per_page, has_more: has_more },
      )
    end

    def positive_integer_param(value, key, default:)
      return default if value.blank?

      string = value.to_s.strip
      raise Discourse::InvalidParameters.new(key) if !string.match?(/\A[1-9]\d*\z/)

      string.to_i
    end
  end
end
