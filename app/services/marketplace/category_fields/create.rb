# frozen_string_literal: true

module Marketplace
  class CategoryFields::Create
    include Service::Base

    params do
      attribute :category_id, :integer
      attribute :key, :string
      attribute :label, :string
      attribute :type, :string
      attribute :required, :boolean
      attribute :enabled, :boolean
      attribute :position, :integer
      attribute :placeholder, :string
      attribute :help_text, :string
      attribute :choices

      validates :category_id, :key, :label, :type, :position, presence: true
      validates :required, :enabled, inclusion: { in: [true, false] }
    end

    policy :admin
    model :category

    transaction do
      model :field_definition, :build_field_definition
      model :field_definition, :save_field_definition
    end

    private

    def admin(guardian:)
      guardian.is_admin?
    end

    def fetch_category(params:)
      Marketplace::Category.find_by(id: params.category_id)
    end

    def build_field_definition(category:, params:)
      category.field_definitions.build(
        key: params.key.to_s.strip.downcase.gsub(/[\s-]+/, "_"),
        label: params.label,
        field_type: params.type,
        required: params.required,
        enabled: params.enabled,
        position: params.position,
        placeholder: params.placeholder.presence,
        help_text: params.help_text.presence,
        choices: normalized_choices(params.choices),
      )
    end

    def save_field_definition(field_definition:)
      field_definition.save
      field_definition
    end

    def normalized_choices(choices)
      choices = choices.to_unsafe_h.values if choices.respond_to?(:to_unsafe_h)
      if choices.is_a?(Array)
        return choices.filter_map do |choice|
          choice = choice.to_unsafe_h if choice.respond_to?(:to_unsafe_h)
          choice.presence
        end
      end

      choices.presence || []
    end
  end
end
