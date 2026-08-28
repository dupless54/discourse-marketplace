# frozen_string_literal: true

module Marketplace
  class OffersController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME
    requires_login

    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 50
    ROLES = %w[buyer seller]
    STATUSES = %w[pending accepted rejected withdrawn expired]

    rescue_from Marketplace::TransactionInvariantViolation do
      render(
        json: failed_json.merge(error_type: "listing_unavailable"),
        status: :conflict,
      )
    end

    def mine
      role = params[:role].presence || "buyer"
      raise Discourse::InvalidParameters.new(:role) if !ROLES.include?(role)

      scope =
        Marketplace::Offer
          .includes(:buyer, :seller, :listing, :accepted_transaction)
          .where(role == "buyer" ? { buyer_id: current_user.id } : { seller_id: current_user.id })

      scope = apply_status_filter(scope, params[:status]) if params[:status].present?
      render_offer_page(scope)
    end

    def listing
      listing = Marketplace::Listing.find_by(id: params[:listing_id])
      raise Discourse::NotFound if listing.blank?
      raise Discourse::NotFound if !guardian.can_see_marketplace_listing?(listing)

      scope =
        Marketplace::Offer
          .includes(:buyer, :seller, :listing, :accepted_transaction)
          .where(listing_id: listing.id)

      if current_user.id != listing.seller_id && !guardian.is_staff?
        scope = scope.where(buyer_id: current_user.id)
      end

      render_offer_page(scope)
    end

    def show
      offer =
        Marketplace::Offer
          .includes(:buyer, :seller, :listing, :accepted_transaction)
          .find_by(id: params[:id])
      raise Discourse::NotFound if offer.blank?
      raise Discourse::NotFound if !guardian.can_see_marketplace_offer?(offer)

      render_serialized(offer, Marketplace::OfferSerializer, root: "offer")
    end

    def create
      Marketplace::Offers::Create.call(service_params) do |result|
        on_success do |offer:|
          render_serialized(offer, Marketplace::OfferSerializer, root: "offer")
        end
        on_model_not_found(:listing) { raise Discourse::NotFound }
        on_failed_policy(:can_create_marketplace_offer) { raise Discourse::InvalidAccess }
        on_failed_contract { render(json: failed_json, status: :unprocessable_entity) }
        on_failure { render_offer_failure(result) }
      end
    end

    def counter
      run_offer_mutation(Marketplace::Offers::Counter, :can_respond_marketplace_offer)
    end

    def reject
      run_offer_mutation(Marketplace::Offers::Reject, :can_respond_marketplace_offer)
    end

    def withdraw
      run_offer_mutation(Marketplace::Offers::Withdraw, :can_withdraw_marketplace_offer)
    end

    def accept
      Marketplace::Offers::Accept.call(
        service_params.deep_merge(params: { offer_id: params[:id] }),
      ) do |result|
        on_success do |offer:, transaction:|
          render_json_dump(
            offer: serialize_data(offer, Marketplace::OfferSerializer, root: false),
            transaction:
              serialize_data(transaction, Marketplace::TransactionSerializer, root: false),
          )
        end
        on_model_not_found(:offer) { raise Discourse::NotFound }
        on_model_not_found(:listing) { raise Discourse::NotFound }
        on_failed_policy(:can_respond_marketplace_offer) { raise Discourse::NotFound }
        on_failed_contract { render(json: failed_json, status: :unprocessable_entity) }
        on_failure { render_offer_failure(result) }
      end
    end

    private

    def run_offer_mutation(service_class, policy_name)
      service_class.call(
        service_params.deep_merge(params: { offer_id: params[:id] }),
      ) do |result|
        on_success do |offer:|
          render_serialized(offer, Marketplace::OfferSerializer, root: "offer")
        end
        on_model_not_found(:offer) { raise Discourse::NotFound }
        on_failed_policy(policy_name) { raise Discourse::NotFound }
        on_failed_contract { render(json: failed_json, status: :unprocessable_entity) }
        on_failure { render_offer_failure(result) }
      end
    end

    def render_offer_failure(result)
      error_type =
        %i[
          offer_already_pending
          buyer_has_pending_transaction
          listing_unavailable
          offer_expired
          offer_not_pending
          offer_not_below_asking_price
          offer_above_asking_price
          offer_amount_unchanged
          offer_currency_changed
        ].find { |key| result[key] }

      status =
        if %i[
             offer_already_pending
             buyer_has_pending_transaction
             listing_unavailable
             offer_expired
             offer_currency_changed
           ].include?(error_type)
          :conflict
        else
          :unprocessable_entity
        end

      render(
        json: failed_json.merge(error_type: error_type&.to_s || "offer_invalid"),
        status: status,
      )
    end

    def apply_status_filter(scope, status)
      raise Discourse::InvalidParameters.new(:status) if !STATUSES.include?(status)

      now = Time.current
      case status
      when "pending"
        scope.where(status: Marketplace::Offer.statuses[:pending]).where("expires_at > ?", now)
      when "expired"
        scope.where(status: Marketplace::Offer.statuses[:pending]).where("expires_at <= ?", now).or(
          scope.where(status: Marketplace::Offer.statuses[:expired]),
        )
      else
        scope.where(status: Marketplace::Offer.statuses.fetch(status))
      end
    end

    def render_offer_page(scope)
      page = positive_integer_param(params[:page], :page, default: 1)
      per_page =
        [
          positive_integer_param(params[:per_page], :per_page, default: DEFAULT_PER_PAGE),
          MAX_PER_PAGE,
        ].min

      records =
        scope
          .order(updated_at: :desc, id: :desc)
          .limit(per_page + 1)
          .offset((page - 1) * per_page)
          .to_a
      has_more = records.size > per_page
      records = records.first(per_page)

      render_json_dump(
        offers: serialize_data(records, Marketplace::OfferSerializer),
        pagination: {
          page: page,
          per_page: per_page,
          has_more: has_more,
        },
      )
    end

    def positive_integer_param(value, key, default: nil)
      return default if value.blank?

      str = value.to_s.strip
      raise Discourse::InvalidParameters.new(key) if !str.match?(/\A[1-9]\d*\z/)

      str.to_i
    end
  end
end
