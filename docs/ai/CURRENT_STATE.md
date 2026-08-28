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

Current source/tests and current GitHub state override this checkpoint if they ever disagree
with it.
