# frozen_string_literal: true

module Marketplace
  class ListingsController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME
    requires_login only: %i[create update update_status transaction mine]

    def index
      result = Marketplace::ListingQuery.new(params: params).results

      render_json_dump(
        listings: serialize_data(result[:records], Marketplace::ListingBrowseSerializer),
        pagination: {
          page: result[:page],
          per_page: result[:per_page],
          has_more: result[:has_more],
        },
      )
    end

    # Returns the current user's own listings across every status (draft,
    # active, reserved, sold, archived) so a seller can find a listing again
    # after leaving its detail page -- the public #index intentionally never
    # returns anything but active/enabled-category listings, so this is the
    # only way an owner can rediscover a draft or archived listing of theirs.
    # Scoped entirely by the WHERE clause on the current user's id, the same
    # reasoning already used by #transaction: no separate Guardian predicate
    # is needed, since no row outside the viewer's own listings can ever be
    # returned.
    def mine
      page = positive_integer_param(params[:page], :page, default: 1)
      per_page =
        [
          positive_integer_param(
            params[:per_page],
            :per_page,
            default: Marketplace::ListingQuery::DEFAULT_PER_PAGE,
          ),
          Marketplace::ListingQuery::MAX_PER_PAGE,
        ].min

      scope =
        Marketplace::Listing
          .includes(:seller)
          .where(seller_id: current_user.id)
          .order(created_at: :desc, id: :desc)

      records = scope.limit(per_page + 1).offset((page - 1) * per_page).to_a
      has_more = records.size > per_page
      records = records.first(per_page)

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

    # This path is both the Ember listing-detail route and the JSON API a
    # listing's viewer fetches from -- resolved by request format, the same
    # convention core itself uses (e.g. UsersController#show,
    # BadgesController#index), rather than by a second, competing route.
    # Direct navigation/F5 (Accept: text/html) gets the SPA shell with no
    # data access at all; Ember then re-requests this same URL itself via
    # ajax() (Accept: application/json), which reaches the json branch below
    # completely unchanged from before.
    def show
      respond_to do |format|
        format.html { render "default/empty" }
        format.json do
          listing = Marketplace::Listing.find_by(id: params[:id])
          raise Discourse::NotFound if listing.blank?
          raise Discourse::NotFound if !guardian.can_see_marketplace_listing?(listing)

          render_serialized(listing, Marketplace::ListingDetailSerializer, root: "listing")
        end
      end
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

    # Lets a listing's viewer discover their own open transaction on it
    # (if any) without a general "my transactions" index -- scoped
    # entirely by the WHERE clause itself (buyer_id/seller_id = current
    # user), so no separate Guardian predicate is needed: no row outside
    # the viewer's own participation can ever be returned. The existing
    # partial unique index on (listing_id) WHERE status <> 20 serves this
    # exact open-transaction query. Cancelled transactions intentionally
    # return 404 so an active listing can start a new transaction cleanly.
    def transaction
      listing = Marketplace::Listing.find_by(id: params[:id])
      raise Discourse::NotFound if listing.blank?

      record =
        Marketplace::Transaction
          .where(listing_id: listing.id)
          .where("buyer_id = :uid OR seller_id = :uid", uid: current_user.id)
          .where.not(status: Marketplace::Transaction.statuses[:cancelled])
          .first
      raise Discourse::NotFound if record.blank?

      render_serialized(record, Marketplace::TransactionSerializer, root: "transaction")
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

    private

    # Strict, matching Marketplace::ListingQuery: only digit strings are
    # accepted, so "abc", "1.5", "-1", and "" all raise rather than silently
    # coercing to 0/1 via to_i.
    def positive_integer_param(value, key, default:)
      return default if value.blank?

      str = value.to_s.strip
      raise Discourse::InvalidParameters.new(key) if !str.match?(/\A[1-9]\d*\z/)

      str.to_i
    end
  end
end
