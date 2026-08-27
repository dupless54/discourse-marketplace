# frozen_string_literal: true

module Marketplace
  class Categories::Create
    include Service::Base

    params do
      attribute :name, :string
      attribute :slug, :string
      attribute :position, :integer
      attribute :enabled, :boolean

      validates :name, :slug, :position, presence: true
      validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
      validates :enabled, inclusion: { in: [true, false] }
    end

    policy :admin

    transaction do
      model :category, :build_category
      model :category, :save_category
    end

    private

    def admin(guardian:)
      guardian.is_admin?
    end

    def build_category(params:)
      Marketplace::Category.new(
        name: params.name,
        slug: params.slug,
        position: params.position,
        enabled: params.enabled,
      )
    end

    def save_category(category:)
      category.save
      category
    end
  end
end
