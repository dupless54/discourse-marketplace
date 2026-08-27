# Trade Reputation Integration Contract

Status: current, reflects `lib/marketplace/trade_contract.rb` as merged on `main`
(`VERSION = 1`). This is the entire public surface Marketplace exposes to the
Trade Reputation plugin. See `docs/MARKETPLACE_ARCHITECTURE.md` §7 for design
rationale; this file is the short reference a Trade Reputation integrator
actually needs.

## Hard boundary

Trade Reputation may call `Marketplace::TradeContract` methods and hold
`transaction_id` values. It may not:
- query `marketplace_transactions`, `marketplace_listings`, or any other
  `marketplace_*` table directly,
- `belongs_to`/associate against a `Marketplace::*` model,
- share a Marketplace service context, or
- reference `Marketplace::Transaction` / `Marketplace::Listing` constants.

Marketplace, symmetrically, never reads or writes any table owned by Trade
Reputation. Guard integration code on `defined?(::Marketplace::TradeContract)`
plus a `Marketplace::TradeContract::VERSION` check, not a plugin manifest
field (no such manifest exists in core).

## API

```ruby
Marketplace::TradeContract::VERSION # => 1

Marketplace::TradeContract.completed_transaction_info(transaction_id)
# -> Marketplace::TradeContract::TransactionInfo | nil
```

`TransactionInfo` is an immutable `Data` object (no setters, no `save`/
`update`) with exactly these fields today:

| field | type | notes |
|---|---|---|
| `transaction_id` | Integer | |
| `buyer_id` | Integer | |
| `seller_id` | Integer | |
| `completed_at` | Time | |

It does not expose `listing_id` or `status`. The method name already encodes
eligibility (see below), so there is no separate "is it completed" check to
get wrong.

### Input handling

Only an actual `Integer` is accepted — not a numeric string, `nil`, or a
float. Any non-`Integer` or non-positive value returns `nil` without raising.
The contract never lets an `ActiveRecord::RecordNotFound` or any other
Marketplace-internal exception cross the plugin boundary.

### Result semantics

| `transaction_id` refers to... | result |
|---|---|
| an unknown id | `nil` |
| a `pending` transaction | `nil` |
| a `cancelled` transaction | `nil` |
| a `completed` transaction | populated `TransactionInfo` |

A non-`nil` result is therefore both the existence check and the eligibility
check: "may user A review user B for this transaction?" reduces to "is
`buyer_id`/`seller_id` one of A/B, and is the result non-`nil`."

## Delivery notes

`Marketplace::TradeContract.completed_transaction_info` is a point-in-time
lookup, not a feed — call it at submission time, not just in response to the
completion event below, so it stays correct even for transactions completed
before Trade Reputation was installed or enabled, or during a lost-event
window.

A best-effort `:marketplace_transaction_completed` event also fires once per
real `pending -> completed` transition, payload is the scalar
`transaction_id` (`Integer`), nothing else. It is not durable (no retry, no
outbox) and must never be treated as the source of truth — only as a hint to
go call `completed_transaction_info`. See architecture doc §7 for exact
firing/non-firing cases.

## Versioning

`VERSION` bumps only on a breaking change to `TransactionInfo`'s shape or to
`completed_transaction_info`'s semantics. Trade Reputation should check it at
boot and refuse to integrate against an unexpected value rather than assume
compatibility.

## Known pending change

An open Marketplace PR (`feature/v1-trade-detail-contract`) adds a
`listing_id` field to `TransactionInfo`, additively (existing callers using
keyword access are unaffected; `VERSION` stays `1`). This document reflects
the contract as currently merged on `main`; update the `TransactionInfo`
field table above once that PR lands.
