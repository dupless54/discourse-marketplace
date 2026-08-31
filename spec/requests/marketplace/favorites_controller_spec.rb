# frozen_string_literal: true

describe Marketplace::FavoritesController do
  fab!(:user)
  fab!(:other_user, :user)
  fab!(:seller, :user)
  fab!(:category, :marketplace_category)
  fab!(:listing) do
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[:active],
      published_at: 1.hour.ago,
    )
  end

  before do
    SiteSetting.marketplace_enabled = true
    SiteSetting.marketplace_allowed_currencies = "USD|EUR"
  end

  describe "#create" do
    it "requires authentication" do
      post "/marketplace/listings/#{listing.id}/favorite.json"

      expect(response.status).to eq(403)
    end

    it "favorites a visible listing for the current user" do
      sign_in(user)

      expect { post "/marketplace/listings/#{listing.id}/favorite.json" }.to change {
        Marketplace::Favorite.where(user_id: user.id, listing_id: listing.id).count
      }.by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["favorited"]).to eq(true)
    end

    it "is idempotent when the same listing is favorited twice" do
      sign_in(user)

      2.times { post "/marketplace/listings/#{listing.id}/favorite.json" }

      expect(response.status).to eq(200)
      expect(Marketplace::Favorite.where(user_id: user.id, listing_id: listing.id).count).to eq(1)
    end

    it "masks a listing the user cannot see" do
      draft =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:draft],
        )
      sign_in(user)

      post "/marketplace/listings/#{draft.id}/favorite.json"

      expect(response.status).to eq(404)
      expect(Marketplace::Favorite.where(user_id: user.id, listing_id: draft.id)).to be_empty
    end
  end

  describe "#destroy" do
    it "removes only the current user's favorite and is idempotent" do
      Fabricate(:marketplace_favorite, user: user, listing: listing)
      Fabricate(:marketplace_favorite, user: other_user, listing: listing)
      sign_in(user)

      2.times { delete "/marketplace/listings/#{listing.id}/favorite.json" }

      expect(response.status).to eq(200)
      expect(response.parsed_body["favorited"]).to eq(false)
      expect(Marketplace::Favorite.exists?(user_id: user.id, listing_id: listing.id)).to eq(false)
      expect(Marketplace::Favorite.exists?(user_id: other_user.id, listing_id: listing.id)).to eq(
        true,
      )
    end

    it "does not reveal whether an arbitrary listing id exists" do
      sign_in(user)

      delete "/marketplace/listings/999999999/favorite.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["favorited"]).to eq(false)
    end
  end

  describe "#index" do
    it "requires authentication" do
      get "/marketplace/favorites.json"

      expect(response.status).to eq(403)
    end

    it "returns only the current user's visible favorites newest first" do
      older =
        Fabricate(
          :marketplace_listing,
          seller: seller,
          category: category,
          status: Marketplace::Listing.statuses[:active],
          published_at: 2.hours.ago,
        )
      own_old =
        Fabricate(:marketplace_favorite, user: user, listing: older, created_at: 2.hours.ago)
      own_new =
        Fabricate(:marketplace_favorite, user: user, listing: listing, created_at: 1.hour.ago)
      Fabricate(:marketplace_favorite, user: other_user, listing: older)
      sign_in(user)

      get "/marketplace/favorites.json"

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["listings"].map { |item| item["id"] }).to eq(
        [own_new.listing_id, own_old.listing_id],
      )
      expect(body["listings"].map { |item| item["favorited"] }.uniq).to eq([true])
    end

    it "omits favorites that are no longer visible because their category is disabled" do
      favorite = Fabricate(:marketplace_favorite, user: user, listing: listing)
      favorite.listing.category.update!(enabled: false)
      sign_in(user)

      get "/marketplace/favorites.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["listings"]).to eq([])
    end
  end

  describe "favorite state on listing APIs" do
    it "marks the current user's favorite on browse and detail" do
      Fabricate(:marketplace_favorite, user: user, listing: listing)
      sign_in(user)

      get "/marketplace/listings.json"
      expect(response.status).to eq(200)
      browsed = response.parsed_body["listings"].find { |item| item["id"] == listing.id }
      expect(browsed["favorited"]).to eq(true)

      get "/marketplace/listings/#{listing.id}.json"
      expect(response.status).to eq(200)
      expect(response.parsed_body["listing"]["favorited"]).to eq(true)
    end

    it "does not expose another user's favorite state to an anonymous viewer" do
      Fabricate(:marketplace_favorite, user: user, listing: listing)

      get "/marketplace/listings.json"

      expect(response.status).to eq(200)
      anonymous = response.parsed_body["listings"].find { |item| item["id"] == listing.id }
      expect(anonymous["favorited"]).to eq(false)
    end
  end
end
