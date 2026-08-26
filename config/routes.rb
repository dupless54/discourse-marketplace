# frozen_string_literal: true

Marketplace::Engine.routes.draw do
  get "categories" => "categories#index"

  post "listings" => "listings#create"
  get "listings/:id" => "listings#show", constraints: { id: /\d+/ }
  put "listings/:id" => "listings#update", constraints: { id: /\d+/ }
  put "listings/:id/status" => "listings#update_status", constraints: { id: /\d+/ }
end
