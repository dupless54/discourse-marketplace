# Durable decisions

Load only when an architecture or integration choice is relevant.

- Marketplace owns listing and transaction truth; reputation remains a separate consumer.
- `Marketplace::TradeContract` is the supported reputation integration seam; consumers must not couple to Marketplace models/tables/private services.
- Listing state and transaction state remain separate server-authoritative state machines.
- Participant authorization and transition validity are enforced server-side; client state is advisory only.
- Integrity that must survive retries/concurrency belongs in persistence constraints and idempotent transition logic where appropriate.
- Listings carry an `inventory_mode` (single/finite/unlimited). SINGLE keeps the original whole-listing `active->reserved->sold` CAS untouched. FINITE/UNLIMITED never auto-transition `status` on stock changes; `status` stays seller-lifecycle-only (draft/active/archived) and purchasability/browse visibility are derived from `stock_reserved`/`stock_sold`/`stock_quantity`/`expires_at` via `Listing#purchasable?`. The `marketplace_transactions` partial unique index is scoped to `(listing_id, buyer_id)`, not `(listing_id)` alone, so distinct buyers can hold concurrent open transactions on the same listing while one buyer still cannot double-book it.

Do not record temporary PR/CI status here; use `CURRENT_STATE.md` for volatile facts.
