# frozen_string_literal: true

Marketplace::Engine.routes.draw { get "categories" => "categories#index" }
