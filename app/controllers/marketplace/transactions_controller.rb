# frozen_string_literal: true

module Marketplace
  class TransactionsController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME
    requires_login only: %i[show create confirm cancel]

    rescue_from Marketplace::TransactionInvariantViolation do
      render(
        json: failed_json.merge(error_type: "transaction_state_conflict"),
        status: :conflict,
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
  end
end
