# frozen_string_literal: true

module Marketplace
  # Serves the Discourse SPA shell for Marketplace's pure-frontend (Ember)
  # routes: /marketplace, /marketplace/new, /marketplace/mine,
  # /marketplace/transactions, and /marketplace/listings/:id/edit. None of
  # these paths has -- or should ever gain -- a JSON representation of its
  # own, so there is no format branching
  # here (contrast ListingsController#show, which serves both an Ember route
  # and a JSON API at the same path). Direct navigation and a browser refresh
  # (F5) on any of these URLs land here first; Ember then boots from the
  # surrounding application layout and its own route map takes over
  # client-side. Same core mechanism Discourse itself uses for this exact
  # purpose (see e.g. UsersController#account_created, BadgesController#index,
  # and the bundled styleguide plugin's StyleguideController#index).
  class StaticController < ::ApplicationController
    requires_plugin Marketplace::PLUGIN_NAME

    def index
      render "default/empty"
    end
  end
end
