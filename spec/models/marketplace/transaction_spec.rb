# frozen_string_literal: true

describe Marketplace::Transaction do
  fab!(:seller) { Fabricate(:user) }
  fab!(:buyer) { Fabricate(:user) }
  fab!(:staff) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:marketplace_category) }
  fab!(:listing) do
    Fabricate(
      :marketplace_listing,
      seller: seller,
      category: category,
      status: Marketplace::Listing.statuses[:active],
    )
  end

  def build_transaction(**overrides)
    Fabricate.build(:marketplace_transaction, listing: listing, buyer: buyer, seller: seller, **overrides)
  end

  def persist_valid_pending
    Fabricate(:marketplace_transaction, listing: listing, buyer: buyer, seller: seller)
  end

  describe "enum" do
    it "maps status values exactly to pending=0, completed=10, cancelled=20" do
      expect(Marketplace::Transaction.statuses).to eq(
        "pending" => 0,
        "completed" => 10,
        "cancelled" => 20,
      )
    end
  end

  describe "associations" do
    it "belongs to listing" do
      transaction = persist_valid_pending
      expect(transaction.listing).to eq(listing)
    end

    it "resolves the buyer association" do
      transaction = persist_valid_pending
      expect(transaction.buyer).to eq(buyer)
    end

    it "resolves the seller association" do
      transaction = persist_valid_pending
      expect(transaction.seller).to eq(seller)
    end

    it "resolves the optional cancelled_by association once set" do
      transaction = persist_valid_pending
      transaction.update_columns(
        status: Marketplace::Transaction.statuses[:cancelled],
        cancelled_at: Time.zone.now,
        cancelled_by_id: staff.id,
      )
      expect(transaction.reload.cancelled_by).to eq(staff)
    end

    it "allows cancelled_by to be absent" do
      transaction = persist_valid_pending
      expect(transaction.cancelled_by).to be_nil
    end
  end

  describe "self-trade validation" do
    it "rejects buyer == seller at the model level" do
      transaction = build_transaction(seller: buyer)
      expect(transaction).not_to be_valid
      expect(transaction.errors[:buyer_id]).to be_present
    end

    it "is valid when buyer and seller differ" do
      expect(build_transaction).to be_valid
    end
  end

  describe "database CHECK constraints bypassing model validation" do
    it "rejects self-trade at the database level even if model validation is bypassed" do
      transaction = build_transaction(seller: buyer)
      expect { transaction.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects an invalid status integer when ActiveRecord enum protection is bypassed" do
      transaction = persist_valid_pending
      expect do
        Marketplace::Transaction.connection.execute(
          "UPDATE marketplace_transactions SET status = 99 WHERE id = #{transaction.id.to_i}",
        )
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "pending status shape" do
    it "is valid with no confirmations" do
      transaction = persist_valid_pending
      expect(transaction.reload.status).to eq("pending")
    end

    it "is valid with only a buyer confirmation" do
      transaction = persist_valid_pending
      transaction.update_columns(buyer_confirmed_at: Time.zone.now)
      expect(transaction.reload.buyer_confirmed_at).to be_present
    end

    it "is valid with only a seller confirmation" do
      transaction = persist_valid_pending
      transaction.update_columns(seller_confirmed_at: Time.zone.now)
      expect(transaction.reload.seller_confirmed_at).to be_present
    end

    it "rejects both confirmations being present while still pending" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(
          buyer_confirmed_at: Time.zone.now,
          seller_confirmed_at: Time.zone.now,
        )
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "completed status shape" do
    def completed_attributes(overrides = {})
      now = Time.zone.now
      {
        status: Marketplace::Transaction.statuses[:completed],
        buyer_confirmed_at: now,
        seller_confirmed_at: now,
        completed_at: now,
      }.merge(overrides)
    end

    it "is valid with buyer_confirmed_at, seller_confirmed_at, and completed_at all present" do
      transaction = persist_valid_pending
      transaction.update_columns(completed_attributes)
      expect(transaction.reload.status).to eq("completed")
    end

    it "rejects completed without buyer_confirmed_at" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(completed_attributes(buyer_confirmed_at: nil))
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects completed without seller_confirmed_at" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(completed_attributes(seller_confirmed_at: nil))
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects completed without completed_at" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(completed_attributes(completed_at: nil))
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects completed with cancelled_at present" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(completed_attributes(cancelled_at: Time.zone.now))
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects completed with cancelled_by_id present" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(completed_attributes(cancelled_by_id: staff.id))
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "cancelled status shape" do
    def cancelled_attributes(overrides = {})
      {
        status: Marketplace::Transaction.statuses[:cancelled],
        cancelled_at: Time.zone.now,
        cancelled_by_id: staff.id,
      }.merge(overrides)
    end

    it "is valid with cancelled_at and cancelled_by_id and zero confirmations" do
      transaction = persist_valid_pending
      transaction.update_columns(cancelled_attributes)
      expect(transaction.reload.status).to eq("cancelled")
    end

    it "is valid with only a buyer confirmation retained" do
      transaction = persist_valid_pending
      transaction.update_columns(cancelled_attributes(buyer_confirmed_at: Time.zone.now))
      expect(transaction.reload.buyer_confirmed_at).to be_present
    end

    it "is valid with only a seller confirmation retained" do
      transaction = persist_valid_pending
      transaction.update_columns(cancelled_attributes(seller_confirmed_at: Time.zone.now))
      expect(transaction.reload.seller_confirmed_at).to be_present
    end

    it "rejects cancelled without cancelled_at" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(cancelled_attributes(cancelled_at: nil))
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects cancelled without cancelled_by_id" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(cancelled_attributes(cancelled_by_id: nil))
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects cancelled with completed_at present" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(cancelled_attributes(completed_at: Time.zone.now))
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects cancelled with both confirmation timestamps present" do
      transaction = persist_valid_pending
      expect do
        transaction.update_columns(
          cancelled_attributes(
            buyer_confirmed_at: Time.zone.now,
            seller_confirmed_at: Time.zone.now,
          ),
        )
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "partial unique index on listing_id" do
    it "allows the first pending transaction for a listing" do
      expect(persist_valid_pending).to be_persisted
    end

    it "rejects a second non-cancelled transaction for the same listing at the database level" do
      persist_valid_pending
      other_buyer = Fabricate(:user)
      second = build_transaction(buyer: other_buyer)

      expect { second.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "still blocks a new transaction once the existing one is completed" do
      first = persist_valid_pending
      now = Time.zone.now
      first.update_columns(
        status: Marketplace::Transaction.statuses[:completed],
        buyer_confirmed_at: now,
        seller_confirmed_at: now,
        completed_at: now,
      )

      other_buyer = Fabricate(:user)
      second = build_transaction(buyer: other_buyer)

      expect { second.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new pending transaction once the existing one is cancelled" do
      first = persist_valid_pending
      first.update_columns(
        status: Marketplace::Transaction.statuses[:cancelled],
        cancelled_at: Time.zone.now,
        cancelled_by_id: staff.id,
      )

      other_buyer = Fabricate(:user)
      second = build_transaction(buyer: other_buyer)

      expect(second.save!).to eq(true)
    end
  end
end
