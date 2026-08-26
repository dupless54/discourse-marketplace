# frozen_string_literal: true

module Marketplace
  class ListingDetailSerializer < Marketplace::ListingSerializer
    attributes :raw, :cooked, :can_edit

    def can_edit
      scope.can_edit_marketplace_listing?(object)
    end

    def include_raw?
      can_edit
    end
  end
end
