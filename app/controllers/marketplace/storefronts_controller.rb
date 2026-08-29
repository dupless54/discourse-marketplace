# frozen_string_literal: true

module Marketplace
  class StorefrontsController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME

    def show
      respond_to do |format|
        format.html { render "default/empty" }
        format.json do
          storefront_debug!("start:#{params[:username]}")
          guardian.ensure_public_can_see_profiles!
          storefront_debug!("public-profile-ok:#{params[:username]}")

          seller = find_seller
          storefront_debug!(seller.present? ? "seller-found" : "seller-missing")
          raise Discourse::NotFound if seller.blank?
          if !seller.active? && !(current_user&.staff? || SiteSetting.show_inactive_accounts)
            storefront_debug!("seller-inactive")
            raise Discourse::NotFound
          end
          storefront_debug!("seller-active")
          if !guardian.can_see_profile?(seller)
            storefront_debug!("profile-hidden")
            raise Discourse::NotFound
          end
          storefront_debug!("profile-visible")

          result = Marketplace::ListingQuery.new(params: params, seller_id: seller.id).results
          storefront_debug!("query-ok:#{result[:records].size}")
          mark_favorites!(result[:records])
          storefront_debug!("favorites-ok")

          seller_json = serialize_data(seller, BasicUserSerializer)
          storefront_debug!("seller-serialized")
          listings_json = serialize_data(result[:records], Marketplace::ListingBrowseSerializer)
          storefront_debug!("listings-serialized")

          render_json_dump(
            seller: seller_json,
            listings: listings_json,
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

    def storefront_debug!(stage)
      response.headers["X-Marketplace-Storefront-Debug"] = stage if Rails.env.test?
    end

    def find_seller
      username = params[:username].to_s
      seller = User.find_by_username(username)
      return seller if seller.present? || !username.end_with?(".json")

      User.find_by_username(username.delete_suffix(".json"))
    end

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
