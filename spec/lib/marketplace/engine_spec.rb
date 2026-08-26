# frozen_string_literal: true

describe Marketplace::Engine do
  # This is a regression guard for a real production boot failure: the engine
  # previously never registered lib/ as an autoload root at all (no
  # config.autoload_paths entry, no matching require_relative), so
  # Marketplace::TransactionInvariantViolation was unresolvable when
  # TransactionsController's `rescue_from` referenced it during production
  # eager-load. This spec cannot reproduce eager-load timing itself (that
  # requires a real `zeitwerk:check` / production boot -- see
  # docs/MARKETPLACE_ARCHITECTURE.md), but it does prove the two things that
  # actually broke: the autoload root is registered, and every constant that
  # depends on it resolves without a manual require.
  it "registers the plugin's lib directory as an autoload path" do
    expected_path = File.join(described_class.config.root, "lib")

    expect(described_class.config.autoload_paths).to include(expected_path)
  end

  it "resolves TransactionInvariantViolation without a manual require" do
    expect(Marketplace::TransactionInvariantViolation).to be < StandardError
  end

  it "resolves ListingQuery without a manual require" do
    expect(Marketplace::ListingQuery).to be_a(Class)
  end

  it "resolves TradeContract without a manual require" do
    expect(Marketplace::TradeContract).to be_a(Module)
  end
end
