# frozen_string_literal: true

describe Marketplace::GuardianExtension do
  fab!(:seller) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:buyer) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:unrelated_user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:staff) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:marketplace_category) }

  def build_listing(status:, **overrides)
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[status],
      **overrides,
    )
  end

  def build_transaction(
    listing: build_listing(status: :reserved),
    buyer: self.buyer,
    seller: self.seller
  )
    Fabricate(:marketplace_transaction, listing: listing, buyer: buyer, seller: seller)
  end

  def silenced_user
    Fabricate(:user, silenced_till: 1.year.from_now, trust_level: TrustLevel[1])
  end

  def suspended_user
    Fabricate(
      :user,
      suspended_till: 1.year.from_now,
      suspended_at: Time.zone.now,
      trust_level: TrustLevel[1],
    )
  end

  describe "#can_create_marketplace_transaction?" do
    it "is false for a blank listing" do
      expect(buyer.guardian.can_create_marketplace_transaction?(nil)).to eq(false)
    end

    it "is false for an anonymous user" do
      listing = build_listing(status: :active)
      expect(Guardian.new.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "is false for the listing's own seller" do
      listing = build_listing(status: :active)
      expect(seller.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "is true for an unrelated eligible buyer" do
      listing = build_listing(status: :active)
      expect(buyer.guardian.can_create_marketplace_transaction?(listing)).to eq(true)
    end

    it "is false for a silenced buyer" do
      listing = build_listing(status: :active)
      expect(silenced_user.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "is false for a suspended buyer" do
      listing = build_listing(status: :active)
      expect(suspended_user.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "is false for a draft listing" do
      listing = build_listing(status: :draft)
      expect(buyer.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "is false for a reserved listing" do
      listing = build_listing(status: :reserved)
      expect(buyer.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "is false for a sold listing" do
      listing = build_listing(status: :sold)
      expect(buyer.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "is false for an archived listing" do
      listing = build_listing(status: :archived)
      expect(buyer.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "is false when the listing's category is disabled" do
      listing = build_listing(status: :active)
      listing.category.update!(enabled: false)

      expect(buyer.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "gives staff no special create bypass for an invalid listing state" do
      listing = build_listing(status: :draft)
      expect(staff.guardian.can_create_marketplace_transaction?(listing)).to eq(false)
    end

    it "allows an unrelated staff user to create for an active eligible listing as an ordinary buyer" do
      listing = build_listing(status: :active)
      expect(staff.guardian.can_create_marketplace_transaction?(listing)).to eq(true)
    end
  end

  describe "#can_see_marketplace_transaction?" do
    it "is false for a blank transaction" do
      expect(buyer.guardian.can_see_marketplace_transaction?(nil)).to eq(false)
    end

    it "is false for an anonymous user" do
      transaction = build_transaction
      expect(Guardian.new.can_see_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is true for the buyer" do
      transaction = build_transaction
      expect(buyer.guardian.can_see_marketplace_transaction?(transaction)).to eq(true)
    end

    it "is true for the seller" do
      transaction = build_transaction
      expect(seller.guardian.can_see_marketplace_transaction?(transaction)).to eq(true)
    end

    it "is false for an unrelated user" do
      transaction = build_transaction
      expect(unrelated_user.guardian.can_see_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is true for staff" do
      transaction = build_transaction
      expect(staff.guardian.can_see_marketplace_transaction?(transaction)).to eq(true)
    end

    it "remains visible to a participant after the listing's category becomes disabled" do
      listing = build_listing(status: :reserved)
      transaction = build_transaction(listing: listing)
      listing.category.update!(enabled: false)

      expect(buyer.guardian.can_see_marketplace_transaction?(transaction)).to eq(true)
    end
  end

  describe "#can_confirm_marketplace_transaction?" do
    it "is false for a blank transaction" do
      expect(buyer.guardian.can_confirm_marketplace_transaction?(nil)).to eq(false)
    end

    it "is false for an anonymous user" do
      transaction = build_transaction
      expect(Guardian.new.can_confirm_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is true for the buyer" do
      transaction = build_transaction
      expect(buyer.guardian.can_confirm_marketplace_transaction?(transaction)).to eq(true)
    end

    it "is true for the seller" do
      transaction = build_transaction
      expect(seller.guardian.can_confirm_marketplace_transaction?(transaction)).to eq(true)
    end

    it "is false for an unrelated user" do
      transaction = build_transaction
      expect(unrelated_user.guardian.can_confirm_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is false for a silenced participant" do
      silenced_buyer = silenced_user
      transaction = build_transaction(buyer: silenced_buyer)
      expect(silenced_buyer.guardian.can_confirm_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is false for a suspended participant" do
      suspended_buyer = suspended_user
      transaction = build_transaction(buyer: suspended_buyer)
      expect(suspended_buyer.guardian.can_confirm_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is false for staff who is not a participant" do
      transaction = build_transaction
      expect(staff.guardian.can_confirm_marketplace_transaction?(transaction)).to eq(false)
    end

    it "remains eligible for a participant after the listing's category becomes disabled" do
      listing = build_listing(status: :reserved)
      transaction = build_transaction(listing: listing)
      listing.category.update!(enabled: false)

      expect(buyer.guardian.can_confirm_marketplace_transaction?(transaction)).to eq(true)
    end

    it "does not depend on the transaction's pending status" do
      transaction = build_transaction
      now = Time.zone.now
      transaction.update_columns(
        status: Marketplace::Transaction.statuses[:completed],
        buyer_confirmed_at: now,
        seller_confirmed_at: now,
        completed_at: now,
      )

      expect(buyer.guardian.can_confirm_marketplace_transaction?(transaction.reload)).to eq(true)
    end
  end

  describe "#can_cancel_marketplace_transaction?" do
    it "is false for a blank transaction" do
      expect(buyer.guardian.can_cancel_marketplace_transaction?(nil)).to eq(false)
    end

    it "is false for an anonymous user" do
      transaction = build_transaction
      expect(Guardian.new.can_cancel_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is true for the buyer" do
      transaction = build_transaction
      expect(buyer.guardian.can_cancel_marketplace_transaction?(transaction)).to eq(true)
    end

    it "is true for the seller" do
      transaction = build_transaction
      expect(seller.guardian.can_cancel_marketplace_transaction?(transaction)).to eq(true)
    end

    it "is false for an unrelated non-staff user" do
      transaction = build_transaction
      expect(unrelated_user.guardian.can_cancel_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is false for a silenced non-staff participant" do
      silenced_buyer = silenced_user
      transaction = build_transaction(buyer: silenced_buyer)
      expect(silenced_buyer.guardian.can_cancel_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is false for a suspended non-staff participant" do
      suspended_buyer = suspended_user
      transaction = build_transaction(buyer: suspended_buyer)
      expect(suspended_buyer.guardian.can_cancel_marketplace_transaction?(transaction)).to eq(false)
    end

    it "is true for unrelated staff via the moderation override" do
      transaction = build_transaction
      expect(staff.guardian.can_cancel_marketplace_transaction?(transaction)).to eq(true)
    end

    it "remains eligible for a participant after the listing's category becomes disabled" do
      listing = build_listing(status: :reserved)
      transaction = build_transaction(listing: listing)
      listing.category.update!(enabled: false)

      expect(buyer.guardian.can_cancel_marketplace_transaction?(transaction)).to eq(true)
    end

    it "does not depend on the transaction's status" do
      transaction = build_transaction
      transaction.update_columns(
        status: Marketplace::Transaction.statuses[:cancelled],
        cancelled_at: Time.zone.now,
        cancelled_by_id: seller.id,
      )

      expect(buyer.guardian.can_cancel_marketplace_transaction?(transaction.reload)).to eq(true)
    end
  end
end
