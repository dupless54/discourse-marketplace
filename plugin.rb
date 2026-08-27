# frozen_string_literal: true

# name: discourse-marketplace
# about: Native marketplace for listings and buyer/seller transactions
# version: 0.0.1
# authors: Discourse Marketplace
# url: https://github.com/dupless54/discourse-marketplace

enabled_site_setting :marketplace_enabled

module ::Marketplace
  PLUGIN_NAME = "discourse-marketplace"
end

require_relative "lib/marketplace/engine"
require_relative "lib/marketplace/guardian_extension"

after_initialize do
  Discourse::Application.routes.append { mount ::Marketplace::Engine, at: "/marketplace" }

  reloadable_patch { ::Guardian.prepend(Marketplace::GuardianExtension) }

  on(:marketplace_transaction_created) { |transaction_id| Marketplace::Notifier.notify_transaction_created(transaction_id) }
  on(:marketplace_transaction_first_confirmed) { |transaction_id| Marketplace::Notifier.notify_transaction_first_confirmed(transaction_id) }
  on(:marketplace_transaction_completed) { |transaction_id| Marketplace::Notifier.notify_transaction_completed(transaction_id) }
  on(:marketplace_transaction_cancelled) { |transaction_id| Marketplace::Notifier.notify_transaction_cancelled(transaction_id) }
end
