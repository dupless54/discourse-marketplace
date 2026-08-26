# frozen_string_literal: true

module Marketplace
  class Listings::TransitionStatus
    include Service::Base

    ALLOWED_TRANSITIONS = {
      "draft" => "active",
      "active" => "archived",
      "sold" => "archived",
    }.freeze

    params do
      attribute :listing_id, :integer
      attribute :status, :string

      validates :listing_id, presence: true
      validates :status, presence: true, inclusion: { in: ALLOWED_TRANSITIONS.values }
    end

    model :listing
    policy :can_transition_marketplace_listing_status
    policy :transition_allowed

    transaction do
      model :listing, :apply_transition
      model :listing, :save_listing
    end

    private

    def fetch_listing(params:)
      Marketplace::Listing.find_by(id: params.listing_id)
    end

    def can_transition_marketplace_listing_status(guardian:, listing:)
      guardian.can_transition_marketplace_listing_status?(listing)
    end

    def transition_allowed(listing:, params:)
      ALLOWED_TRANSITIONS[listing.status] == params.status
    end

    def apply_transition(listing:, params:)
      listing.status = params.status
      listing.published_at = Time.zone.now if params.status == "active" && listing.published_at.nil?
      listing.closed_at = Time.zone.now if params.status == "archived" && listing.closed_at.nil?
      listing
    end

    def save_listing(listing:)
      listing.save
      listing
    end
  end
end
