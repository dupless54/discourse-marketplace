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

      get "/marketplace"

      expect(response.status).to eq(404)
    end
  end
end
