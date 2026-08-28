# frozen_string_literal: true

RSpec.describe Marketplace::StorefrontsController do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:other_seller) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:category) { Fabricate(:marketplace_category) }

  before do
    SiteSetting.hide_user_profiles_from_public = false
    SiteSetting.hide_new_user_profiles = false
  end

  def active_listing(user:, title:, category: self.category, published_at: Time.current)
    Fabricate(
      :marketplace_listing,
      seller: user,
      category: category,
      title: title,
      status: Marketplace::Listing.statuses[:active],
      published_at: published_at,
    )
  end

  def get_storefront(username, params: {})
    get "/marketplace/sellers/#{username}",
        params: params,
        headers: { "ACCEPT" => "application/json" }
  end

  describe "GET /marketplace/sellers/:username" do
    it "returns only the seller's publicly browseable listings and BasicUser fields" do
      visible = active_listing(user: seller, title: "Visible", published_at: 2.hours.ago)
      active_listing(user: other_seller, title: "Other seller")
      Fabricate(:marketplace_listing, seller: seller, category: category, title: "Draft")
      Fabricate(
        :marketplace_listing,
        seller: seller,
        category: category,
        title: "Expired",
        status: Marketplace::Listing.statuses[:active],
        published_at: 3.hours.ago,
        expires_at: 1.hour.ago,
      )
      disabled_category = Fabricate(:marketplace_category)
      active_listing(user: seller, title: "Disabled category", category: disabled_category)
      disabled_category.update!(enabled: false)

      anonymous_guardian = Guardian.new
      expect(User.find_by_username(seller.username)).to eq(seller)
      expect(seller).to be_active
      expect { anonymous_guardian.ensure_public_can_see_profiles! }.not_to raise_error
      expect(anonymous_guardian.can_see_profile?(seller)).to eq(true)

      expect_any_instance_of(Marketplace::StorefrontsController).to receive(:show).and_call_original
      expect(User).to receive(:find_by_username).with(seller.username).and_call_original
      expect_any_instance_of(Guardian)
        .to receive(:can_see_profile?)
        .with(seller)
        .and_wrap_original do |method, *args|
          result = method.call(*args)
          expect(result).to eq(true)
          result
        end
      expect_any_instance_of(Marketplace::ListingQuery)
        .to receive(:results)
        .and_wrap_original do |method, *args|
          result = method.call(*args)
          expect(result[:records].map(&:id)).to eq([visible.id])
          result
        end
      allow_any_instance_of(Marketplace::StorefrontsController)
        .to receive(:serialize_data)
        .and_wrap_original do |method, *args|
          method.call(*args)
        rescue Discourse::NotFound => e
          raise "storefront serialize_data #{args[1]} raised NotFound: #{e.message}"
        end
      allow_any_instance_of(Marketplace::StorefrontsController)
        .to receive(:render_json_dump)
        .and_wrap_original do |method, *args|
          method.call(*args)
        rescue Discourse::NotFound => e
          raise "storefront render_json_dump raised NotFound: #{e.message}"
        end

      get_storefront(seller.username)

      expect(response.status).to eq(200), response.body
      expect(response.parsed_body.dig("seller", "id")).to eq(seller.id)
      expect(response.parsed_body.dig("seller", "username")).to eq(seller.username)
      expect(response.parsed_body.fetch("seller")).not_to include("email", "trust_level", "admin", "moderator")
      expect(response.parsed_body.fetch("listings").map { |listing| listing["id"] }).to eq([visible.id])
    end

    it "paginates the seller's visible listings deterministically" do
      older = active_listing(user: seller, title: "Older", published_at: 2.hours.ago)
      newer = active_listing(user: seller, title: "Newer", published_at: 1.hour.ago)

      get_storefront(seller.username, params: { page: 1, per_page: 1 })

      expect(response.status).to eq(200), response.body
      expect(response.parsed_body.fetch("listings").map { |listing| listing["id"] }).to eq([newer.id])
      expect(response.parsed_body.fetch("pagination")).to eq(
        "page" => 1,
        "per_page" => 1,
        "has_more" => true,
      )

      get_storefront(seller.username, params: { page: 2, per_page: 1 })

      expect(response.status).to eq(200), response.body
      expect(response.parsed_body.fetch("listings").map { |listing| listing["id"] }).to eq([older.id])
      expect(response.parsed_body.dig("pagination", "has_more")).to eq(false)
    end

    it "respects the global public-profile visibility setting for anonymous viewers" do
      SiteSetting.hide_user_profiles_from_public = true
      active_listing(user: seller, title: "Public listing")

      get_storefront(seller.username)

      expect(response.status).to eq(404)
      expect(response.body).not_to include(seller.username)
    end

    it "masks a seller whose profile the viewer cannot see" do
      SiteSetting.allow_users_to_hide_profile = true
      seller.user_option.update!(hide_profile: true)
      viewer = Fabricate(:user, trust_level: TrustLevel[2])
      sign_in(viewer)
      active_listing(user: seller, title: "Still public listing")

      get_storefront(seller.username)

      expect(response.status).to eq(404)
      expect(response.body).not_to include(seller.username)
    end

    it "returns 404 for an unknown seller without leaking profile data" do
      get_storefront("definitely-missing-user")

      expect(response.status).to eq(404)
      expect(response.body).not_to include("definitely-missing-user")
    end

    it "serves the SPA shell on direct HTML navigation without resolving the seller" do
      get "/marketplace/sellers/definitely-missing-user", headers: { "ACCEPT" => "text/html" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end
  end
end
