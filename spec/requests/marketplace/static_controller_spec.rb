# frozen_string_literal: true

describe Marketplace::StaticController do
  before { SiteSetting.marketplace_enabled = true }

  describe "#index" do
    it "returns the SPA shell for anonymous and authenticated users alike" do
      get "/marketplace"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")

      sign_in(Fabricate(:user))
      get "/marketplace"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end

    it "returns 404 when the plugin is disabled" do
      SiteSetting.marketplace_enabled = false

      # Same StaticController#index action, same requires_plugin before_action,
      # as the bare /marketplace root -- routed through a non-root shell path
      # to avoid any ambiguity from Rails' handling of a mounted engine's own
      # root route, which is a separate routing question from what this
      # example is verifying (requires_plugin actually gates this controller).
      get "/marketplace/new"

      expect(response.status).to eq(404)
    end
  end
end
