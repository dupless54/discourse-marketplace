# frozen_string_literal: true

module Marketplace
  class Categories::Update
    include Service::Base

    params do
      attribute :category_id, :integer
      attribute :name, :string
      attribute :slug, :string
      attribute :position, :integer
      attribute :enabled, :boolean

      validates :category_id, :name, :slug, :position, presence: true
      validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
      validates :enabled, inclusion: { in: [true, false] }
    end

    policy :admin
    model :category

    transaction { model :category, :update_category }

    private

    def admin(guardian:)
      guardian.is_admin?
    end

    def fetch_category(params:)
      Marketplace::Category.find_by(id: params.category_id)
    end

    def update_category(category:, params:)
      category.assign_attributes(
        name: params.name,
        slug: params.slug,
        position: params.position,
        enabled: params.enabled,
      )
      category.save
      category
    end
  end
end
