# frozen_string_literal: true

Marketplace::Engine.routes.draw do
  # Pure-frontend (Ember) routes -- see StaticController for why these carry
  # no JSON behavior and never should. listings/:id is deliberately absent
  # here: it is both an Ember route and the JSON API below, resolved by
  # format inside ListingsController#show, not by a second route.
  # Favorites is also absent: FavoritesController#index already serves both
  # the SPA shell and its JSON collection at the same path via respond_to.
  root to: "static#index"
  get "new" => "static#index"
  get "mine" => "static#index"
  get "offers" => "static#index"
  get "listings/:id/edit" => "static#index", constraints: { id: /\d+/ }
  get "transactions" => "static#index"

  get "categories" => "categories#index"
  get "favorites" => "favorites#index"
  get "sellers/:username" => "storefronts#show"

  namespace :admin do
    resources :categories, only: %i[index create update destroy] do
      resources :fields, only: %i[create update], controller: "category_fields"
    end
  end

  get "listings" => "listings#index"
  post "listings" => "listings#create"
  get "listings/mine" => "listings#mine"
  get "listings/:id" => "listings#show", constraints: { id: /\d+/ }
  put "listings/:id" => "listings#update", constraints: { id: /\d+/ }
  put "listings/:id/status" => "listings#update_status", constraints: { id: /\d+/ }
  get "listings/:id/transactions" => "listings#transactions", constraints: { id: /\d+/ }
  get "listings/:listing_id/offers" => "offers#listing", constraints: { listing_id: /\d+/ }
  post "listings/:listing_id/favorite" => "favorites#create", constraints: { listing_id: /\d+/ }
  delete "listings/:listing_id/favorite" => "favorites#destroy", constraints: { listing_id: /\d+/ }

  get "offers/mine" => "offers#mine"
  post "offers" => "offers#create"
  get "offers/:id" => "offers#show", constraints: { id: /\d+/ }
  post "offers/:id/counter" => "offers#counter", constraints: { id: /\d+/ }
  post "offers/:id/accept" => "offers#accept", constraints: { id: /\d+/ }
  post "offers/:id/reject" => "offers#reject", constraints: { id: /\d+/ }
  post "offers/:id/withdraw" => "offers#withdraw", constraints: { id: /\d+/ }

  get "transactions/mine" => "transactions#mine"
  post "transactions" => "transactions#create"
  get "transactions/:id" => "transactions#show", constraints: { id: /\d+/ }
  post "transactions/:id/confirm" => "transactions#confirm", constraints: { id: /\d+/ }
  post "transactions/:id/cancel" => "transactions#cancel", constraints: { id: /\d+/ }
end
