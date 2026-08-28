# frozen_string_literal: true

module Marketplace
  module Admin
    class CategoryFieldsController < ::Admin::AdminController
      requires_plugin Marketplace::PLUGIN_NAME

      def create
        Marketplace::CategoryFields::Create.call(
          service_params.deep_merge(params: { category_id: params[:category_id] }),
        ) do
          on_success { |field_definition:| render_field(field_definition, status: :created) }
          on_failure { render(json: failed_json, status: :unprocessable_entity) }
          on_failed_contract { |contract| render_contract_errors(contract) }
          on_failed_policy(:admin) { raise Discourse::InvalidAccess }
          on_model_not_found(:category) { raise Discourse::NotFound }
          on_model_errors(:field_definition) { |model| render_model_errors(model) }
        end
      end

      def update
        Marketplace::CategoryFields::Update.call(
          service_params.deep_merge(
            params: {
              category_id: params[:category_id],
              field_definition_id: params[:id],
            },
          ),
        ) do
          on_success { |field_definition:| render_field(field_definition) }
          on_failure { render(json: failed_json, status: :unprocessable_entity) }
          on_failed_contract { |contract| render_contract_errors(contract) }
          on_failed_policy(:admin) { raise Discourse::InvalidAccess }
          on_model_not_found(:category) { raise Discourse::NotFound }
          on_model_not_found(:field_definition) { raise Discourse::NotFound }
          on_model_errors(:field_definition) { |model| render_model_errors(model) }
        end
      end

      private

      def render_field(field_definition, status: :ok)
        render(
          json: {
            field_definition:
              field_definition.public_schema.merge(
                id: field_definition.id,
                enabled: field_definition.enabled,
              ),
          },
          status: status,
        )
      end

      def render_contract_errors(contract)
        render(
          json: failed_json.merge(errors: contract.errors.full_messages),
          status: :bad_request,
        )
      end

      def render_model_errors(model)
        render(
          json: failed_json.merge(errors: model.errors.full_messages),
          status: :unprocessable_entity,
        )
      end
    end
  end
end
