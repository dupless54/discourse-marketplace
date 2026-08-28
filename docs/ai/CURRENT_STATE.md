# Current state

Main baseline: `a3f44a845629a51d5ceb04696332740a60ebd295`

Marketplace V1 (per `docs/PROJECT_BRIEF.md`) is COMPLETE on `main`. All areas are merged and
documented in `docs/MARKETPLACE_ARCHITECTURE.md`: listing lifecycle (create/edit/publish/
archive), browse/search/filter, My Listings (PR #16), transaction lifecycle + notifications,
`Marketplace::TradeContract` v1 plus the pre-existing `marketplace-transaction-after-actions`
`PluginOutlet` (§7), categories/admin, and the listing image/attachment upload UI (PR #17).
Frontend QUnit coverage exists for all three interactive components (§9).

No open blockers. Remaining items are intentional V1 scope cuts, not gaps (see
`docs/MARKETPLACE_ARCHITECTURE.md` §10): URL-addressable browse/search state, a main-nav/
sidebar entry point to `/marketplace`, and the plugin stylesheet (§1).

Inventory/lifetime work (post-V1): listings now carry `inventory_mode` (single/finite/
unlimited), `stock_quantity`/`stock_reserved`/`stock_sold`, and optional `expires_at`. See
`docs/ai/DECISIONS.md` for the design summary. `Marketplace::TradeContract` is unchanged.

PR #23 fixed multi-transaction listing semantics (pending-only listing+buyer uniqueness,
concurrent buyers on finite/unlimited listings, exact transaction selection via
`listing_id` + `transaction_id`).

Transaction Center (post-V1, this change): `marketplace_transactions` now carries an
immutable snapshot (`listing_title_snapshot`/`price_cents_snapshot`/`currency_snapshot`,
nullable, captured only on creation, no backfill for pre-existing rows -- see
`docs/MARKETPLACE_ARCHITECTURE.md` §2). `GET /marketplace/transactions/mine`
(`Marketplace::TransactionSummarySerializer`) is the current user's own buyer/seller
transaction history, and `/marketplace/transactions` is the corresponding SPA route
("İşlemlerim" / "My Transactions"), linked from the Marketplace browse header. Still not
built: URL-addressable browse/search state and a main-nav/sidebar entry point to
`/marketplace` itself (Transaction Center is discoverable only from inside `/marketplace`).

Current source/tests and current GitHub state override this checkpoint if they ever disagree
with it.
