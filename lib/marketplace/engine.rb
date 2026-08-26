# frozen_string_literal: true

module Marketplace
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace Marketplace
  end
end
