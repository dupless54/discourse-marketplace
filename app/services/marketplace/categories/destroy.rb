# frozen_string_literal: true

module Marketplace
  class Categories::Destroy
    include Service::Base

    params do
      attribute :category_id, :integer

      validates :category_id, presence: true
    end

    policy :admin
    model :category

    transaction do
      step :lock_category
      policy :unused
      step :destroy_category
    end

    private

    def admin(guardian:)
      guardian.is_admin?
    end

    def fetch_category(params:)
      Marketplace::Category.find_by(id: params.category_id)
    end

    def lock_category(category:)
      category.lock!
    end

    def unused(category:)
      !Marketplace::Listing.exists?(category_id: category.id)
    end

    def destroy_category(category:)
      category.destroy!
    end
  end
end
