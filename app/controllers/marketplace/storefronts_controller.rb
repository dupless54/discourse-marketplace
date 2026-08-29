# frozen_string_literal: true

module Marketplace
  class StorefrontsController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME

    def show
      respond_to do |format|
        format.html { render "default/empty" }
        format.json do
          guardian.ensure_public_can_see_profiles!

          seller = User.find_by_username(params[:username])
          raise Discourse::NotFound if seller.blank?
          if !seller.active? && !(current_user&.staff? || SiteSetting.show_inactive_accounts)
            raise Discourse::NotFound
          end
          raise Discourse::NotFound if !guardian.can_see_profile?(seller)

          result = Marketplace::ListingQuery.new(params: params, seller_id: seller.id).results
          mark_favorites!(result[:records])

          render_json_dump(
            seller: serialize_data(seller, BasicUserSerializer, root: false),
            listings: serialize_data(result[:records], Marketplace::ListingBrowseSerializer),
            pagination: {
              page: result[:page],
              per_page: result[:per_page],
              has_more: result[:has_more],
            },
          )
        end
      end
    end

    private

    def mark_favorites!(listings)
      return if listings.blank?

      listings.each do |listing|
        listing.instance_variable_set(:@marketplace_favorited_by_viewer, false)
      end

      return if current_user.blank?

      favorite_ids =
        Marketplace::Favorite
          .where(user_id: current_user.id, listing_id: listings.map(&:id))
          .pluck(:listing_id)
          .to_set

      listings.each do |listing|
        listing.instance_variable_set(
          :@marketplace_favorited_by_viewer,
          favorite_ids.include?(listing.id),
        )
      end
    end
  end
end
