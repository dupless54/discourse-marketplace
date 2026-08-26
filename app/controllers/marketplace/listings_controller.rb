# frozen_string_literal: true

module Marketplace
  class ListingsController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME
    requires_login only: %i[create update update_status]

    def create
      Marketplace::Listings::Create.call(service_params) do |result|
        on_success do |listing:|
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
      listing = Marketplace::Listing.find_by(id: params[:id])
      raise Discourse::NotFound if listing.blank?
      raise Discourse::NotFound if !guardian.can_see_marketplace_listing?(listing)

      render_serialized(listing, Marketplace::ListingDetailSerializer, root: "listing")
    end

    def update
      Marketplace::Listings::Update.call(
        service_params.deep_merge(params: { listing_id: params[:id] }),
      ) do |result|
        on_success do |listing:|
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

    def update_status
      Marketplace::Listings::TransitionStatus.call(
        service_params.deep_merge(
          params: {
            listing_id: params[:id],
            status: params[:status],
          },
        ),
      ) do |result|
        on_success do |listing:|
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
  end
end
