# frozen_string_literal: true

RSpec.describe "Marketplace mobile layout" do
  fab!(:seller, :user)
  fab!(:current_user, :user)
  fab!(:admin, :admin)
  fab!(:category) do
    Fabricate(
      :marketplace_category,
      name: "Mobile category with a deliberately long responsive label",
      slug: "mobile-overflow-category",
    )
  end
  fab!(:seller_listing) do
    long_description_token = "marketplaceoverflow" * 30

    Fabricate(
      :marketplace_unlimited_listing,
      seller: seller,
      category: category,
      title: "Mobile overflow regression listing with a long responsive title",
      raw: long_description_token,
      cooked: "<p>#{long_description_token}</p>",
      status: Marketplace::Listing.statuses[:active],
      published_at: 1.hour.ago,
      price_cents: 12_500,
      currency: "USD",
    )
  end
  fab!(:own_listing) do
    Fabricate(
      :marketplace_unlimited_listing,
      seller: current_user,
      category: category,
      title: "Current user mobile listing",
      status: Marketplace::Listing.statuses[:active],
      published_at: 2.hours.ago,
    )
  end
  fab!(:favorite) { Fabricate(:marketplace_favorite, user: current_user, listing: seller_listing) }
  fab!(:offer) do
    Fabricate(
      :marketplace_offer,
      listing: seller_listing,
      buyer: current_user,
      proposed_by: current_user,
    )
  end
  fab!(:transaction_listing) do
    Fabricate(
      :marketplace_unlimited_listing,
      seller: seller,
      category: category,
      title: "Mobile transaction listing",
      status: Marketplace::Listing.statuses[:reserved],
      published_at: 3.hours.ago,
    )
  end
  fab!(:transaction) do
    Fabricate(
      :marketplace_transaction,
      listing: transaction_listing,
      buyer: current_user,
      seller: seller,
    )
  end

  before { SiteSetting.marketplace_enabled = true }

  def expect_no_page_horizontal_overflow
    overflow =
      page.evaluate_script(
        "document.documentElement.scrollWidth - document.documentElement.clientWidth",
      )

    expect(overflow).to be <= 1
  end

  it "keeps every user-facing Marketplace route inside a phone viewport" do
    sign_in(current_user)

    resize_window(width: 400, height: 844) do
      routes = [
        ["/marketplace", ".marketplace-browse"],
        ["/marketplace/listings/#{seller_listing.id}", ".marketplace-listing-detail"],
        ["/marketplace/new", ".marketplace-listing-form"],
        ["/marketplace/mine", ".marketplace-my-listings"],
        ["/marketplace/favorites", ".marketplace-favorites"],
        ["/marketplace/sellers/#{seller.username}", ".marketplace-storefront"],
        ["/marketplace/offers", ".marketplace-offer-center"],
        ["/marketplace/transactions", ".marketplace-transaction-center"],
      ]

      routes.each do |path, selector|
        visit path

        expect(page).to have_css("html.mobile-view")
        expect(page).to have_css(selector)
        expect_no_page_horizontal_overflow
      end

      expect(page).to have_css(".marketplace-transaction-center__card")
    end
  end

  it "keeps mobile listing detail content and primary actions usable" do
    sign_in(current_user)

    resize_window(width: 400, height: 844) do
      visit "/marketplace/listings/#{seller_listing.id}"

      expect(page).to have_css("html.mobile-view")
      expect(page).to have_css(".marketplace-listing-detail__title", text: seller_listing.title)
      expect(page).to have_css(".marketplace-listing-detail__panel")
      expect(page).to have_css(".marketplace-listing-detail__description")
      expect(page).to have_button(I18n.t("js.marketplace.listing.buy_button"))
      expect_no_page_horizontal_overflow
    end
  end

  it "keeps the new-listing form usable without horizontal page overflow" do
    sign_in(current_user)

    resize_window(width: 400, height: 844) do
      visit "/marketplace/new"

      expect(page).to have_css("html.mobile-view")
      expect(page).to have_field("marketplace-listing-title")
      expect(page).to have_field("marketplace-listing-description")
      expect(page).to have_select("marketplace-listing-category")
      expect(page).to have_button(I18n.t("js.marketplace.form.submit_create"))
      expect_no_page_horizontal_overflow
    end
  end

  it "keeps Marketplace category administration inside a phone viewport" do
    sign_in(admin)

    resize_window(width: 400, height: 844) do
      visit "/admin/plugins/discourse-marketplace/categories"

      expect(page).to have_css("html.mobile-view")
      expect(page).to have_css(".marketplace-category-admin")
      expect(page).to have_css(".marketplace-category-admin__category")
      expect_no_page_horizontal_overflow
    end
  end
end
