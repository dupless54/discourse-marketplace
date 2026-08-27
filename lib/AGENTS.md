# Marketplace library layer

- `Marketplace::TradeContract` is a stable public consumer boundary; return immutable data, not ActiveRecord objects.
- Keep contract version/shape changes deliberate, documented, and covered by contract specs.
- Guardian helpers are authorization seams, not UI hints.
- Listing queries must remain bounded, indexed, deterministic, and free of avoidable N+1 work.
- Keep `lib/marketplace` compatible with the repository's Zeitwerk/autoloading convention.
