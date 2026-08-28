# frozen_string_literal: true

module Marketplace
  class TransactionsController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME
    requires_login only: %i[show create confirm cancel mine]

    MINE_DEFAULT_PER_PAGE = 20
    MINE_MAX_PER_PAGE = 50
    MINE_ROLES = %w[buyer seller]
    MINE_STATUSES = %w[pending completed cancelled]

    rescue_from Marketplace::TransactionInvariantViolation do
      render(
        json: failed_json.merge(error_type: "transaction_state_conflict"),
        status: :conflict,
      )
    end

    # The current user's own Transaction Center feed: every row is scoped
    # by buyer_id/seller_id == current_user.id directly in the WHERE
    # clause, the same non-enumerable-by-construction pattern already used
    # by ListingsController#mine -- there is no user_id/username input to
    # this action at all, so no separate Guardian predicate is needed.
    def mine
      role = params[:role].presence || "buyer"
      raise Discourse::InvalidParameters.new(:role) if !MINE_ROLES.include?(role)

      scope =
        Marketplace::Transaction
          .includes(:buyer, :seller, :listing)
          .where(role == "buyer" ? { buyer_id: current_user.id } : { seller_id: current_user.id })

      if params[:status].present?
        raise Discourse::InvalidParameters.new(:status) if !MINE_STATUSES.include?(params[:status])

        scope = scope.where(status: Marketplace::Transaction.statuses[params[:status]])
      end

      page = positive_integer_param(params[:page], :page, default: 1)
      per_page =
        [
          positive_integer_param(params[:per_page], :per_page, default: MINE_DEFAULT_PER_PAGE),
          MINE_MAX_PER_PAGE,
        ].min

      records =
        scope
          .order(created_at: :desc, id: :desc)
          .limit(per_page + 1)
          .offset((page - 1) * per_page)
          .to_a
      has_more = records.size > per_page
      records = records.first(per_page)

      render_json_dump(
        transactions: serialize_data(records, Marketplace::TransactionSummarySerializer),
        pagination: {
          page: page,
          per_page: per_page,
          has_more: has_more,
        },
      )
    end

    def create
      Marketplace::Transactions::Create.call(service_params) do |result|
        on_success do |transaction:|
          render_serialized(transaction, Marketplace::TransactionSerializer, root: "transaction")
        end
        on_model_not_found(:listing) { raise Discourse::NotFound }
        on_failed_policy(:can_create_marketplace_transaction) { raise Discourse::InvalidAccess }
        on_failed_contract { render(json: failed_json, status: :unprocessable_entity) }
        on_failure do
          if result[:listing_unavailable]
            render(
              json: failed_json.merge(error_type: "listing_unavailable"),
              status: :conflict,
            )
          else
            render(json: failed_json, status: :unprocessable_entity)
          end
        end
      end
    end

    def show
      transaction = Marketplace::Transaction.find_by(id: params[:id])
      raise Discourse::NotFound if transaction.blank?
      raise Discourse::NotFound if !guardian.can_see_marketplace_transaction?(transaction)

      render_serialized(transaction, Marketplace::TransactionSerializer, root: "transaction")
    end

    def confirm
      Marketplace::Transactions::Confirm.call(
        service_params.deep_merge(params: { transaction_id: params[:id] }),
      ) do |result|
        on_success do |transaction:|
          render_serialized(transaction, Marketplace::TransactionSerializer, root: "transaction")
        end
        on_model_not_found(:transaction_record) { raise Discourse::NotFound }
        on_failed_policy(:can_confirm_marketplace_transaction) { raise Discourse::NotFound }
        on_failed_contract { render(json: failed_json, status: :unprocessable_entity) }
        on_failure do
          if result[:transaction_not_confirmable]
            render(
              json: failed_json.merge(error_type: "transaction_not_confirmable"),
              status: :unprocessable_entity,
            )
          else
            render(json: failed_json, status: :unprocessable_entity)
          end
        end
      end
    end

    def cancel
      Marketplace::Transactions::Cancel.call(
        service_params.deep_merge(params: { transaction_id: params[:id] }),
      ) do |result|
        on_success do |transaction:|
          render_serialized(transaction, Marketplace::TransactionSerializer, root: "transaction")
        end
        on_model_not_found(:transaction_record) { raise Discourse::NotFound }
        on_failed_policy(:can_cancel_marketplace_transaction) { raise Discourse::NotFound }
        on_failed_contract { render(json: failed_json, status: :unprocessable_entity) }
        on_failure do
          if result[:transaction_not_cancellable]
            render(
              json: failed_json.merge(error_type: "transaction_not_cancellable"),
              status: :unprocessable_entity,
            )
          else
            render(json: failed_json, status: :unprocessable_entity)
          end
        end
      end
    end

    private

    # Strict, matching Marketplace::ListingQuery/ListingsController: only
    # digit strings are accepted, so "abc", "1.5", "-1", and "" all raise
    # rather than silently coercing to 0/1 via to_i.
    def positive_integer_param(value, key, default: nil)
      return default if value.blank?

      str = value.to_s.strip
      raise Discourse::InvalidParameters.new(key) if !str.match?(/\A[1-9]\d*\z/)

      str.to_i
    end
  end
end
