# frozen_string_literal: true

Marketplace::Engine.routes.draw do
  get "categories" => "categories#index"

  get "listings" => "listings#index"
  post "listings" => "listings#create"
  get "listings/:id" => "listings#show", constraints: { id: /\d+/ }
  put "listings/:id" => "listings#update", constraints: { id: /\d+/ }
  put "listings/:id/status" => "listings#update_status", constraints: { id: /\d+/ }
  get "listings/:id/transaction" => "listings#transaction", constraints: { id: /\d+/ }

  post "transactions" => "transactions#create"
  get "transactions/:id" => "transactions#show", constraints: { id: /\d+/ }
  post "transactions/:id/confirm" => "transactions#confirm", constraints: { id: /\d+/ }
  post "transactions/:id/cancel" => "transactions#cancel", constraints: { id: /\d+/ }
end
