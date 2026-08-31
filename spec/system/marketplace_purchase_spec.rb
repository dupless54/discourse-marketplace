# frozen_string_literal: true

describe "Marketplace purchase flow", type: :system do
  fab!(:seller) { Fabricate(:user) }
  fab!(:current_user) { Fabricate(:user) }
  fab!(:category) { Fabricate(:marketplace_category) }
  fab!(:listing) do
    Fabricate(
      :marketplace_unlimited_listing,
      seller: seller,
      category: category,
      title: "System spec marketplace listing",
      status: Marketplace::Listing.statuses[:active],
      price_cents: 12_500,
      currency: "USD",
    )
  end

  before do
    SiteSetting.marketplace_enabled = true
    sign_in(current_user)
  end

  it "lets a buyer open a transaction from an active listing" do
    page.visit("/marketplace/listings/#{listing.id}")

    expect(page).to have_css(".marketplace-listing-detail__title", text: listing.title)
    expect(page).to have_button(I18n.t("js.marketplace.listing.buy_button"))

    click_button(I18n.t("js.marketplace.listing.buy_button"))

    expect(page).to have_css(
      ".marketplace-transaction",
      text: I18n.t("js.marketplace.transaction.status.pending"),
    )
    expect(page).to have_button(I18n.t("js.marketplace.transaction.confirm_button"))
    expect(page).to have_button(I18n.t("js.marketplace.transaction.cancel_button"))
    expect(page).to have_no_button(I18n.t("js.marketplace.listing.buy_button"))
  end
end
