# frozen_string_literal: true

# name: discourse-marketplace
# about: Native marketplace for listings and buyer/seller transactions
# version: 0.0.1
# authors: Discourse Marketplace
# url: https://github.com/dupless54/discourse-marketplace

enabled_site_setting :marketplace_enabled

register_asset "stylesheets/common/marketplace.scss"
register_asset "stylesheets/common/marketplace-favorites.scss"
register_asset "stylesheets/common/marketplace-offers.scss"
register_asset "stylesheets/common/marketplace-dynamic-filters.scss"

module ::Marketplace
  PLUGIN_NAME = "discourse-marketplace"
end

require_relative "lib/marketplace/engine"
require_relative "lib/marketplace/guardian_extension"

after_initialize do
  add_admin_route(
    "marketplace.admin.title",
    "discourse-marketplace",
    { use_new_show_route: true },
  )

  Discourse::Application.routes.append do
    get "/admin/plugins/discourse-marketplace/categories" => "admin/plugins#index",
        constraints: StaffConstraint.new
    mount ::Marketplace::Engine, at: "/marketplace"
  end

  reloadable_patch { ::Guardian.prepend(Marketplace::GuardianExtension) }

  on(:marketplace_transaction_created) { |transaction_id| Marketplace::Notifier.notify_transaction_created(transaction_id) }
  on(:marketplace_transaction_first_confirmed) { |transaction_id| Marketplace::Notifier.notify_transaction_first_confirmed(transaction_id) }
  on(:marketplace_transaction_completed) { |transaction_id| Marketplace::Notifier.notify_transaction_completed(transaction_id) }
  on(:marketplace_transaction_cancelled) { |transaction_id| Marketplace::Notifier.notify_transaction_cancelled(transaction_id) }

  on(:marketplace_offer_created) { |offer_id| Marketplace::Notifier.notify_offer_created(offer_id) }
  on(:marketplace_offer_countered) { |offer_id| Marketplace::Notifier.notify_offer_countered(offer_id) }
  on(:marketplace_offer_accepted) { |offer_id| Marketplace::Notifier.notify_offer_accepted(offer_id) }
  on(:marketplace_offer_rejected) { |offer_id| Marketplace::Notifier.notify_offer_rejected(offer_id) }
  on(:marketplace_offer_withdrawn) { |offer_id| Marketplace::Notifier.notify_offer_withdrawn(offer_id) }
end