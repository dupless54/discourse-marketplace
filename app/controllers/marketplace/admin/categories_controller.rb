# frozen_string_literal: true

module Marketplace
  module Admin
    class CategoriesController < ::Admin::AdminController
      requires_plugin Marketplace::PLUGIN_NAME

      def index
        categories = Marketplace::Category.includes(:field_definitions).order(:position, :id)

        render_json_dump(
          categories: serialize_data(categories, Marketplace::AdminCategorySerializer),
        )
      end

      def create
        Marketplace::Categories::Create.call(service_params) do
          on_success do |category:|
            category.field_definitions.load
            render_serialized(
              category,
              Marketplace::AdminCategorySerializer,
              root: "category",
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
          on_failed_policy(:admin) { raise Discourse::InvalidAccess }
          on_model_errors(:category) do |model|
            render(
              json: failed_json.merge(errors: model.errors.full_messages),
              status: :unprocessable_entity,
            )
          end
        end
      end

      def update
        Marketplace::Categories::Update.call(
          service_params.deep_merge(params: { category_id: params[:id] }),
        ) do
          on_success do |category:|
            category.field_definitions.load
            render_serialized(
              category,
              Marketplace::AdminCategorySerializer,
              root: "category",
            )
          end
          on_failure { render(json: failed_json, status: :unprocessable_entity) }
          on_failed_contract do |contract|
            render(
              json: failed_json.merge(errors: contract.errors.full_messages),
              status: :bad_request,
            )
          end
          on_failed_policy(:admin) { raise Discourse::InvalidAccess }
          on_model_not_found(:category) { raise Discourse::NotFound }
          on_model_errors(:category) do |model|
            render(
              json: failed_json.merge(errors: model.errors.full_messages),
              status: :unprocessable_entity,
            )
          end
        end
      end

      def destroy
        Marketplace::Categories::Destroy.call(
          service_params.deep_merge(params: { category_id: params[:id] }),
        ) do
          on_success { head :no_content }
          on_failure { render(json: failed_json, status: :unprocessable_entity) }
          on_failed_contract do |contract|
            render(
              json: failed_json.merge(errors: contract.errors.full_messages),
              status: :bad_request,
            )
          end
          on_failed_policy(:admin) { raise Discourse::InvalidAccess }
          on_failed_policy(:unused) do
            render(
              json: failed_json.merge(errors: [I18n.t("marketplace.errors.category_in_use")]),
              status: :conflict,
            )
          end
          on_model_not_found(:category) { raise Discourse::NotFound }
        end
      end
    end
  end
end
