# frozen_string_literal: true

module Marketplace
  class ListingsController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME
    requires_login only: %i[create update update_status transactions mine]

    TRANSACTIONS_DEFAULT_PER_PAGE = 20
    TRANSACTIONS_MAX_PER_PAGE = 50

    def index
      result = Marketplace::ListingQuery.new(params: params).results
      mark_favorites!(result[:records])

      render_json_dump(
        listings: serialize_data(result[:records], Marketplace::ListingBrowseSerializer),
        pagination: {
          page: result[:page],
          per_page: result[:per_page],
          has_more: result[:has_more],
        },
      )
    end

    def mine
      page = positive_integer_param(params[:page], :page, default: 1)
      per_page = [
        positive_integer_param(
          params[:per_page],
          :per_page,
          default: Marketplace::ListingQuery::DEFAULT_PER_PAGE,
        ),
        Marketplace::ListingQuery::MAX_PER_PAGE,
      ].min

      scope =
        Marketplace::Listing
          .includes(:seller, :category)
          .where(seller_id: current_user.id)
          .order(created_at: :desc, id: :desc)

      records = scope.limit(per_page + 1).offset((page - 1) * per_page).to_a
      has_more = records.size > per_page
      records = records.first(per_page)
      mark_favorites!(records)

      render_json_dump(
        listings: serialize_data(records, Marketplace::ListingBrowseSerializer),
        pagination: {
          page: page,
          per_page: per_page,
          has_more: has_more,
        },
      )
    end

    def create
      Marketplace::Listings::Create.call(service_params) do |result|
        on_success do |listing:|
          mark_favorites!([listing])
          render_serialized(
            listing,
            Marketplace::ListingDetailSerializer,
            root: "listing",
            status: :created,
          )
        end
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_failed_contract do |contract|
          render(
            json: failed_json.merge(errors: contract.errors.full_messages),
            status: :bad_request,
          )
        end
        on_model_not_found(:category) { raise Discourse::NotFound }
        on_failed_policy(:can_create_marketplace_listing) { raise Discourse::InvalidAccess }
        on_model_errors(:listing) do |model|
          render(
            json: failed_json.merge(errors: model.errors.full_messages),
            status: :unprocessable_entity,
          )
        end
      end
    end

    def show
      respond_to do |format|
        format.html { render "default/empty" }
        format.json do
          listing = Marketplace::Listing.find_by(id: params[:id])
          raise Discourse::NotFound if listing.blank?
          raise Discourse::NotFound if !guardian.can_see_marketplace_listing?(listing)

          mark_favorites!([listing])
          render_serialized(listing, Marketplace::ListingDetailSerializer, root: "listing")
        end
      end
    end

    def update
      Marketplace::Listings::Update.call(
        service_params.deep_merge(params: { listing_id: params[:id] }),
      ) do |result|
        on_success do |listing:|
          mark_favorites!([listing])
          render_serialized(listing, Marketplace::ListingDetailSerializer, root: "listing")
        end
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_failed_contract do |contract|
          render(
            json: failed_json.merge(errors: contract.errors.full_messages),
            status: :bad_request,
          )
        end
        on_model_not_found(:listing) { raise Discourse::NotFound }
        on_model_not_found(:category) { raise Discourse::NotFound }
        on_failed_policy(:can_edit_marketplace_listing) { raise Discourse::NotFound }
        on_model_errors(:listing) do |model|
          render(
            json: failed_json.merge(errors: model.errors.full_messages),
            status: :unprocessable_entity,
          )
        end
      end
    end

    def transactions
      listing = Marketplace::Listing.find_by(id: params[:id])
      raise Discourse::NotFound if listing.blank?

      scope =
        Marketplace::Transaction.includes(:buyer, :seller, :listing).where(listing_id: listing.id)

      scope =
        if listing.seller_id == current_user.id
          scope.where(seller_id: current_user.id)
        else
          scope.where(buyer_id: current_user.id)
        end

      if params[:transaction_id].present?
        transaction_id = positive_integer_param(params[:transaction_id], :transaction_id)
        record = scope.find_by(id: transaction_id)
        raise Discourse::NotFound if record.blank?

        return(
          render_json_dump(
            transactions: serialize_data([record], Marketplace::TransactionSerializer),
            pagination: {
              page: 1,
              per_page: 1,
              has_more: false,
            },
          )
        )
      end

      page = positive_integer_param(params[:page], :page, default: 1)
      per_page = [
        positive_integer_param(
          params[:per_page],
          :per_page,
          default: TRANSACTIONS_DEFAULT_PER_PAGE,
        ),
        TRANSACTIONS_MAX_PER_PAGE,
      ].min

      records =
        scope
          .order(status: :asc, created_at: :desc, id: :desc)
          .limit(per_page + 1)
          .offset((page - 1) * per_page)
          .to_a
      has_more = records.size > per_page
      records = records.first(per_page)

      render_json_dump(
        transactions: serialize_data(records, Marketplace::TransactionSerializer),
        pagination: {
          page: page,
          per_page: per_page,
          has_more: has_more,
        },
      )
    end

    def update_status
      Marketplace::Listings::TransitionStatus.call(
        service_params.deep_merge(params: { listing_id: params[:id], status: params[:status] }),
      ) do |result|
        on_success do |listing:|
          mark_favorites!([listing])
          render_serialized(listing, Marketplace::ListingDetailSerializer, root: "listing")
        end
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_failed_contract do |contract|
          render(
            json: failed_json.merge(errors: contract.errors.full_messages),
            status: :bad_request,
          )
        end
        on_model_not_found(:listing) { raise Discourse::NotFound }
        on_failed_policy(:can_transition_marketplace_listing_status) { raise Discourse::NotFound }
        on_failed_policy(:transition_allowed) do
          render(json: failed_json, status: :unprocessable_entity)
        end
        on_model_errors(:listing) do |model|
          render(
            json: failed_json.merge(errors: model.errors.full_messages),
            status: :unprocessable_entity,
          )
        end
      end
    end

    private

    def mark_favorites!(listings)
      return if listings.blank?

      # Always initialize the viewer-specific state so a reused ActiveRecord
      # instance can never carry a previous request's favorite flag into an
      # anonymous or different-user serialization.
      listings.each do |listing|
        listing.instance_variable_set(:@marketplace_favorited_by_viewer, false)
      end

      return if current_user.blank?

      favorite_ids =
        Marketplace::Favorite
          .where(user_id: current_user.id, listing_id: listings.map(&:id))
          .pluck(:listing_id)
          .to_set

      listings.each do |listing|
        listing.instance_variable_set(
          :@marketplace_favorited_by_viewer,
          favorite_ids.include?(listing.id),
        )
      end
    end

    def positive_integer_param(value, key, default: nil)
      return default if value.blank?

      str = value.to_s.strip
      raise Discourse::InvalidParameters.new(key) if !str.match?(/\A[1-9]\d*\z/)

      str.to_i
    end
  end
end
