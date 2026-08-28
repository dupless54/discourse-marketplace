# frozen_string_literal: true

class CreateMarketplaceOffers < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_offers do |t|
      t.bigint :listing_id, null: false
      t.integer :buyer_id, null: false
      t.integer :seller_id, null: false
      t.integer :proposed_by_id, null: false
      t.integer :responded_by_id
      t.integer :status, null: false, default: 0
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, limit: 3
      t.datetime :expires_at, null: false
      t.datetime :responded_at
      t.bigint :accepted_transaction_id

      t.timestamps
    end

    add_index :marketplace_offers,
              %i[listing_id buyer_id],
              unique: true,
              where: "status = 0",
              name: "idx_marketplace_offers_listing_buyer_pending"

    add_index :marketplace_offers,
              %i[buyer_id status updated_at id],
              order: { updated_at: :desc, id: :desc },
              name: "idx_marketplace_offers_buyer_status_updated"

    add_index :marketplace_offers,
              %i[seller_id status updated_at id],
              order: { updated_at: :desc, id: :desc },
              name: "idx_marketplace_offers_seller_status_updated"

    add_index :marketplace_offers,
              %i[listing_id status updated_at id],
              order: { updated_at: :desc, id: :desc },
              name: "idx_marketplace_offers_listing_status_updated"

    add_index :marketplace_offers,
              :accepted_transaction_id,
              unique: true,
              where: "accepted_transaction_id IS NOT NULL",
              name: "idx_marketplace_offers_accepted_transaction"

    add_foreign_key :marketplace_offers,
                    :marketplace_listings,
                    column: :listing_id,
                    on_delete: :restrict
    add_foreign_key :marketplace_offers,
                    :marketplace_transactions,
                    column: :accepted_transaction_id,
                    on_delete: :restrict

    add_check_constraint :marketplace_offers,
                         "buyer_id <> seller_id",
                         name: "marketplace_offers_distinct_participants"
    add_check_constraint :marketplace_offers,
                         "proposed_by_id = buyer_id OR proposed_by_id = seller_id",
                         name: "marketplace_offers_proposer_is_participant"
    add_check_constraint :marketplace_offers,
                         "responded_by_id IS NULL OR responded_by_id = buyer_id OR responded_by_id = seller_id",
                         name: "marketplace_offers_responder_is_participant"
    add_check_constraint :marketplace_offers,
                         "amount_cents > 0",
                         name: "marketplace_offers_positive_amount"
    add_check_constraint :marketplace_offers,
                         "status IN (0, 10, 20, 30, 40)",
                         name: "marketplace_offers_valid_status"

    create_table :marketplace_offer_events do |t|
      t.bigint :offer_id, null: false
      t.integer :actor_id, null: false
      t.integer :event_type, null: false
      t.bigint :amount_cents
      t.string :currency, limit: 3
      t.datetime :created_at, null: false
    end

    add_index :marketplace_offer_events,
              %i[offer_id id],
              name: "idx_marketplace_offer_events_offer_id"

    add_foreign_key :marketplace_offer_events,
                    :marketplace_offers,
                    column: :offer_id,
                    on_delete: :cascade

    add_check_constraint :marketplace_offer_events,
                         "amount_cents IS NULL OR amount_cents > 0",
                         name: "marketplace_offer_events_positive_amount"
    add_check_constraint :marketplace_offer_events,
                         "event_type IN (0, 10, 20, 30, 40, 50)",
                         name: "marketplace_offer_events_valid_type"
  end
end
