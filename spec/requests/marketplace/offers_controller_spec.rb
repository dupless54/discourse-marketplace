# frozen_string_literal: true

describe Marketplace::OffersController do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:other_buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:unrelated_user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category) { Fabricate(:marketplace_category) }

  before do
    SiteSetting.marketplace_enabled = true
    SiteSetting.marketplace_allowed_currencies = "USD|EUR"
    SiteSetting.marketplace_offer_expiry_hours = 48
  end

  def active_listing(**overrides)
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[:active],
      price_cents: 10_000,
      currency: "USD",
      **overrides,
    )
  end

  def offer_for(listing:, buyer: self.buyer, proposed_by: buyer, **overrides)
    Fabricate(
      :marketplace_offer,
      listing: listing,
      buyer: buyer,
      seller: listing.seller,
      proposed_by: proposed_by,
      amount_cents: 8_000,
      currency: listing.currency,
      **overrides,
    )
  end

  describe "#create" do
    it "creates a pending offer below asking price and records the immutable proposal event" do
      listing = active_listing
      sign_in(buyer)

      post "/marketplace/offers.json",
           params: {
             listing_id: listing.id,
             amount_cents: 8_500,
           }

      expect(response.status).to eq(200)
      offer = Marketplace::Offer.find(response.parsed_body.dig("offer", "id"))
      expect(offer.buyer_id).to eq(buyer.id)
      expect(offer.seller_id).to eq(seller.id)
      expect(offer.proposed_by_id).to eq(buyer.id)
      expect(offer.amount_cents).to eq(8_500)
      expect(offer.currency).to eq("USD")
      expect(offer).to be_pending
      expect(offer.expires_at).to be_within(5.seconds).of(48.hours.from_now)
      expect(offer.events.pluck(:event_type, :actor_id, :amount_cents)).to eq(
        [["proposed", buyer.id, 8_500]],
      )
    end

    it "rejects an asking-price offer and keeps the database unchanged" do
      listing = active_listing
      sign_in(buyer)

      post "/marketplace/offers.json",
           params: {
             listing_id: listing.id,
             amount_cents: listing.price_cents,
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["error_type"]).to eq("offer_not_below_asking_price")
      expect(Marketplace::Offer.count).to eq(0)
    end

    it "does not let a seller offer on their own listing" do
      listing = active_listing
      sign_in(seller)

      post "/marketplace/offers.json", params: { listing_id: listing.id, amount_cents: 8_000 }

      expect(response.status).to eq(403)
      expect(Marketplace::Offer.count).to eq(0)
    end

    it "returns conflict for a second live offer from the same buyer" do
      listing = active_listing
      offer_for(listing: listing)
      sign_in(buyer)

      post "/marketplace/offers.json", params: { listing_id: listing.id, amount_cents: 7_500 }

      expect(response.status).to eq(409)
      expect(response.parsed_body["error_type"]).to eq("offer_already_pending")
      expect(Marketplace::Offer.where(listing_id: listing.id, buyer_id: buyer.id).count).to eq(1)
    end

    it "expires a stale pending row and permits a replacement offer" do
      listing = active_listing
      stale = offer_for(listing: listing, expires_at: 1.hour.ago)
      sign_in(buyer)

      post "/marketplace/offers.json", params: { listing_id: listing.id, amount_cents: 7_500 }

      expect(response.status).to eq(200)
      expect(stale.reload).to be_expired
      expect(stale.events.last.event_type).to eq("expired")
      expect(stale.events.last.actor_id).to be_nil
      expect(Marketplace::Offer.where(listing_id: listing.id, buyer_id: buyer.id).count).to eq(2)
    end
  end

  describe "negotiation" do
    it "lets only the current recipient counter and flips the proposer" do
      listing = active_listing
      offer = offer_for(listing: listing)
      original_expiry = offer.expires_at
      sign_in(seller)

      post "/marketplace/offers/#{offer.id}/counter.json", params: { amount_cents: 9_000 }

      expect(response.status).to eq(200)
      offer.reload
      expect(offer.amount_cents).to eq(9_000)
      expect(offer.proposed_by_id).to eq(seller.id)
      expect(offer.expires_at).to be > original_expiry
      expect(offer.events.last.event_type).to eq("countered")
      expect(offer.events.last.actor_id).to eq(seller.id)

      sign_in(seller)
      post "/marketplace/offers/#{offer.id}/accept.json"
      expect(response.status).to eq(404)
    end

    it "lets the current proposer withdraw but masks the action from unrelated users" do
      listing = active_listing
      offer = offer_for(listing: listing)

      sign_in(unrelated_user)
      post "/marketplace/offers/#{offer.id}/withdraw.json"
      expect(response.status).to eq(404)
      expect(offer.reload).to be_pending

      sign_in(buyer)
      post "/marketplace/offers/#{offer.id}/withdraw.json"
      expect(response.status).to eq(200)
      expect(offer.reload).to be_withdrawn
    end

    it "blocks actions after the offer deadline without mutating the row" do
      listing = active_listing
      offer = offer_for(listing: listing, expires_at: 1.minute.ago)
      sign_in(seller)

      post "/marketplace/offers/#{offer.id}/accept.json"

      expect(response.status).to eq(409)
      expect(response.parsed_body["error_type"]).to eq("offer_expired")
      expect(offer.reload.status).to eq("pending")
      expect(offer.effective_status).to eq("expired")
    end
  end

  describe "#accept" do
    it "atomically creates a transaction at the negotiated price and reserves a single listing" do
      listing = active_listing
      offer = offer_for(listing: listing, amount_cents: 7_750)
      sign_in(seller)

      post "/marketplace/offers/#{offer.id}/accept.json"

      expect(response.status).to eq(200)
      transaction = Marketplace::Transaction.find(response.parsed_body.dig("transaction", "id"))
      expect(transaction.price_cents_snapshot).to eq(7_750)
      expect(transaction.currency_snapshot).to eq("USD")
      expect(transaction.listing_title_snapshot).to eq(listing.title)
      expect(transaction.buyer_id).to eq(buyer.id)
      expect(transaction.seller_id).to eq(seller.id)
      expect(transaction).to be_pending
      expect(listing.reload).to be_reserved
      expect(offer.reload).to be_accepted
      expect(offer.accepted_transaction_id).to eq(transaction.id)
      expect(offer.events.last.event_type).to eq("accepted")
    end

    it "reserves one finite-stock unit without closing the listing" do
      listing =
        active_listing(
          inventory_mode: Marketplace::Listing.inventory_modes[:finite],
          stock_quantity: 3,
          stock_reserved: 0,
          stock_sold: 0,
        )
      offer = offer_for(listing: listing)
      sign_in(seller)

      post "/marketplace/offers/#{offer.id}/accept.json"

      expect(response.status).to eq(200)
      listing.reload
      expect(listing.status).to eq("active")
      expect(listing.stock_reserved).to eq(1)
    end

    it "returns the same transaction when the accepting recipient replays the request" do
      listing = active_listing
      offer = offer_for(listing: listing)
      sign_in(seller)

      post "/marketplace/offers/#{offer.id}/accept.json"
      first_id = response.parsed_body.dig("transaction", "id")
      post "/marketplace/offers/#{offer.id}/accept.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("transaction", "id")).to eq(first_id)
      expect(Marketplace::Transaction.where(listing_id: listing.id, buyer_id: buyer.id).count).to eq(1)
    end
  end

  describe "read isolation" do
    it "lets a buyer see only their own offer while the seller sees all listing offers" do
      listing = active_listing
      mine = offer_for(listing: listing, buyer: buyer)
      theirs = offer_for(listing: listing, buyer: other_buyer)

      sign_in(buyer)
      get "/marketplace/listings/#{listing.id}/offers.json"
      expect(response.status).to eq(200)
      expect(response.parsed_body["offers"].map { |row| row["id"] }).to eq([mine.id])

      sign_in(seller)
      get "/marketplace/listings/#{listing.id}/offers.json"
      expect(response.status).to eq(200)
      expect(response.parsed_body["offers"].map { |row| row["id"] }).to contain_exactly(
        mine.id,
        theirs.id,
      )
    end

    it "masks an offer from unrelated users" do
      listing = active_listing
      offer = offer_for(listing: listing)
      sign_in(unrelated_user)

      get "/marketplace/offers/#{offer.id}.json"

      expect(response.status).to eq(404)
    end
  end
end
