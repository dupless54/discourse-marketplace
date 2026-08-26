# frozen_string_literal: true

describe Marketplace::TransactionsController do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:other_buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:unrelated_user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:staff) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:marketplace_category) }

  before do
    SiteSetting.marketplace_enabled = true
    SiteSetting.marketplace_allowed_currencies = "USD|EUR"
  end

  def json_body
    response.parsed_body["transaction"]
  end

  def build_listing(status: :active, **overrides)
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[status],
      **overrides,
    )
  end

  def build_transaction(
    status: :pending,
    listing: build_listing(status: :reserved),
    buyer: self.buyer,
    seller: self.seller,
    **overrides
  )
    Fabricate(
      :marketplace_transaction,
      listing: listing,
      buyer: buyer,
      seller: seller,
      status: Marketplace::Transaction.statuses[status],
      **overrides,
    )
  end

  def build_completed_transaction
    now = Time.current
    build_transaction(
      status: :completed,
      listing: build_listing(status: :sold),
      buyer_confirmed_at: now,
      seller_confirmed_at: now,
      completed_at: now,
    )
  end

  describe "#create" do
    it "lets a logged-in non-seller buyer start a transaction with the exact expected fields" do
      listing = build_listing
      sign_in(buyer)

      post "/marketplace/transactions.json", params: { listing_id: listing.id }

      expect(response.status).to eq(200)
      expect(response.parsed_body.keys).to contain_exactly("transaction")
      expect(json_body.keys).to contain_exactly(
        "id",
        "listing_id",
        "buyer_id",
        "seller_id",
        "status",
        "buyer_confirmed_at",
        "seller_confirmed_at",
        "completed_at",
        "cancelled_at",
        "cancelled_by_id",
        "created_at",
        "updated_at",
      )
      expect(json_body["buyer_id"]).to eq(buyer.id)
      expect(json_body["seller_id"]).to eq(listing.seller_id)
      expect(json_body["listing_id"]).to eq(listing.id)
      expect(json_body["status"]).to eq("pending")
      expect(listing.reload.status).to eq("reserved")
    end

    it "returns the same transaction on a same-buyer replay without creating a second one" do
      listing = build_listing
      sign_in(buyer)

      post "/marketplace/transactions.json", params: { listing_id: listing.id }
      first_id = json_body["id"]

      post "/marketplace/transactions.json", params: { listing_id: listing.id }

      expect(response.status).to eq(200)
      expect(json_body["id"]).to eq(first_id)
      expect(Marketplace::Transaction.where(listing_id: listing.id).count).to eq(1)
    end

    it "returns a masked 409 conflict for a different-buyer contention without leaking the existing transaction" do
      listing = build_listing
      sign_in(buyer)
      post "/marketplace/transactions.json", params: { listing_id: listing.id }
      existing_transaction_id = json_body["id"]

      sign_in(other_buyer)
      post "/marketplace/transactions.json", params: { listing_id: listing.id }

      expect(response.status).to eq(409)
      expect(response.parsed_body["error_type"]).to eq("listing_unavailable")
      expect(response.parsed_body.keys).not_to include("transaction")

      raw = response.body
      expect(raw).not_to include(existing_transaction_id.to_s)
      expect(raw).not_to include(buyer.id.to_s)
      expect(raw).not_to include(seller.id.to_s)
      expect(raw).not_to include("pending")
    end

    it "rejects the listing's own seller with the established policy status" do
      listing = build_listing
      sign_in(seller)

      post "/marketplace/transactions.json", params: { listing_id: listing.id }

      expect(response.status).to eq(403)
      expect(response.parsed_body.keys).not_to include("transaction")
    end

    it "rejects an anonymous request" do
      listing = build_listing
      post "/marketplace/transactions.json", params: { listing_id: listing.id }

      expect(response.status).to eq(403)
    end
  end

  describe "#show" do
    it "allows the buyer to view" do
      transaction = build_transaction
      sign_in(buyer)

      get "/marketplace/transactions/#{transaction.id}.json"

      expect(response.status).to eq(200)
      expect(json_body["id"]).to eq(transaction.id)
    end

    it "allows the seller to view" do
      transaction = build_transaction
      sign_in(seller)

      get "/marketplace/transactions/#{transaction.id}.json"

      expect(response.status).to eq(200)
    end

    it "allows staff to view" do
      transaction = build_transaction
      sign_in(staff)

      get "/marketplace/transactions/#{transaction.id}.json"

      expect(response.status).to eq(200)
    end

    it "returns 404 with no transaction data for an unrelated user" do
      transaction = build_transaction
      sign_in(unrelated_user)

      get "/marketplace/transactions/#{transaction.id}.json"

      expect(response.status).to eq(404)
      expect(response.body).not_to include(transaction.id.to_s)
    end

    it "returns 404 for a missing transaction" do
      sign_in(buyer)
      missing_id = Marketplace::Transaction.maximum(:id).to_i + 1

      get "/marketplace/transactions/#{missing_id}.json"

      expect(response.status).to eq(404)
    end

    it "returns the login-required response for an anonymous request against an existing transaction" do
      transaction = build_transaction

      get "/marketplace/transactions/#{transaction.id}.json"
      existing_status = response.status

      expect(existing_status).not_to eq(200)
      expect(existing_status).not_to eq(404)
      expect(response.body).not_to include(transaction.id.to_s)
      expect(response.parsed_body.keys).not_to include("transaction")
    end

    it "returns the SAME login-required status for an anonymous request against a missing transaction" do
      transaction = build_transaction
      get "/marketplace/transactions/#{transaction.id}.json"
      existing_status = response.status

      missing_id = Marketplace::Transaction.maximum(:id).to_i + 1
      get "/marketplace/transactions/#{missing_id}.json"

      expect(response.status).to eq(existing_status)
      expect(response.parsed_body.keys).not_to include("transaction")
    end

    it "remains showable to a participant once completed" do
      transaction = build_completed_transaction
      sign_in(buyer)

      get "/marketplace/transactions/#{transaction.id}.json"

      expect(response.status).to eq(200)
      expect(json_body["status"]).to eq("completed")
    end
  end

  describe "#confirm" do
    it "lets the buyer make the first confirmation" do
      transaction = build_transaction

      sign_in(buyer)
      post "/marketplace/transactions/#{transaction.id}/confirm.json"

      expect(response.status).to eq(200)
      expect(json_body["status"]).to eq("pending")
      expect(json_body["buyer_confirmed_at"]).to be_present
      expect(json_body["seller_confirmed_at"]).to be_nil
    end

    it "completes the transaction and sells the listing on the second confirmation" do
      listing = build_listing(status: :reserved)
      transaction = build_transaction(listing: listing, seller_confirmed_at: 1.minute.ago)

      sign_in(buyer)
      post "/marketplace/transactions/#{transaction.id}/confirm.json"

      expect(response.status).to eq(200)
      expect(json_body["status"]).to eq("completed")
      expect(json_body["buyer_confirmed_at"]).to be_present
      expect(json_body["seller_confirmed_at"]).to be_present
      expect(json_body["completed_at"]).to be_present
      expect(listing.reload.status).to eq("sold")
    end

    it "succeeds as an idempotent replay for a completed participant" do
      transaction = build_completed_transaction

      sign_in(buyer)
      post "/marketplace/transactions/#{transaction.id}/confirm.json"

      expect(response.status).to eq(200)
      expect(json_body["status"]).to eq("completed")
    end

    it "returns 422 transaction_not_confirmable for a cancelled transaction" do
      transaction =
        build_transaction(status: :cancelled, cancelled_at: Time.current, cancelled_by_id: seller.id)

      sign_in(buyer)
      post "/marketplace/transactions/#{transaction.id}/confirm.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["error_type"]).to eq("transaction_not_confirmable")
      expect(response.parsed_body.keys).not_to include("transaction")
    end

    it "returns 404 with no transaction data for an unrelated user" do
      transaction = build_transaction

      sign_in(unrelated_user)
      post "/marketplace/transactions/#{transaction.id}/confirm.json"

      expect(response.status).to eq(404)
      expect(response.body).not_to include(transaction.id.to_s)
    end

    it "returns 404 for a missing transaction" do
      missing_id = Marketplace::Transaction.maximum(:id).to_i + 1

      sign_in(buyer)
      post "/marketplace/transactions/#{missing_id}/confirm.json"

      expect(response.status).to eq(404)
    end
  end

  describe "#cancel" do
    it "lets a participant cancel a pending transaction" do
      listing = build_listing(status: :reserved)
      transaction = build_transaction(listing: listing)

      sign_in(buyer)
      post "/marketplace/transactions/#{transaction.id}/cancel.json"

      expect(response.status).to eq(200)
      expect(json_body["status"]).to eq("cancelled")
      expect(json_body["cancelled_by_id"]).to eq(buyer.id)
      expect(listing.reload.status).to eq("active")
    end

    it "lets unrelated staff cancel via the moderation override" do
      transaction = build_transaction

      sign_in(staff)
      post "/marketplace/transactions/#{transaction.id}/cancel.json"

      expect(response.status).to eq(200)
      expect(json_body["cancelled_by_id"]).to eq(staff.id)
    end

    it "succeeds as an idempotent replay preserving the original cancellation metadata" do
      transaction = build_transaction

      sign_in(buyer)
      post "/marketplace/transactions/#{transaction.id}/cancel.json"
      original_cancelled_at = json_body["cancelled_at"]

      sign_in(seller)
      post "/marketplace/transactions/#{transaction.id}/cancel.json"

      expect(response.status).to eq(200)
      expect(json_body["cancelled_by_id"]).to eq(buyer.id)
      expect(json_body["cancelled_at"]).to eq(original_cancelled_at)
    end

    it "returns 422 transaction_not_cancellable for a completed transaction" do
      transaction = build_completed_transaction

      sign_in(buyer)
      post "/marketplace/transactions/#{transaction.id}/cancel.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["error_type"]).to eq("transaction_not_cancellable")
      expect(response.parsed_body.keys).not_to include("transaction")
    end

    it "returns 422 transaction_not_cancellable for unrelated staff on a completed transaction" do
      transaction = build_completed_transaction

      sign_in(staff)
      post "/marketplace/transactions/#{transaction.id}/cancel.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["error_type"]).to eq("transaction_not_cancellable")
    end

    it "returns 404 with no transaction data for an unrelated ordinary user" do
      transaction = build_transaction

      sign_in(unrelated_user)
      post "/marketplace/transactions/#{transaction.id}/cancel.json"

      expect(response.status).to eq(404)
      expect(response.body).not_to include(transaction.id.to_s)
    end
  end

  describe "invariant conflict mapping" do
    it "returns a generic 409 transaction_state_conflict without leaking internal state" do
      listing = build_listing(status: :active)
      transaction = build_transaction(listing: listing)

      sign_in(buyer)
      post "/marketplace/transactions/#{transaction.id}/confirm.json"

      expect(response.status).to eq(409)
      expect(response.parsed_body["error_type"]).to eq("transaction_state_conflict")
      expect(response.parsed_body.keys).not_to include("transaction")
      expect(response.body).not_to include("TransactionInvariantViolation")
      expect(response.body).not_to match(/marketplace_transactions|marketplace_listings/)
    end
  end
end
