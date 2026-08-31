# Current state

Current source and tests are authoritative; this file is a compact handoff summary.

Marketplace V1 and the post-V1 marketplace extensions are implemented on `main`:
- listing create/edit/publish/archive, browse/search/category and structured-field filters;
- single/finite/unlimited inventory and optional listing expiry;
- favorites, seller storefronts, offers/counteroffers and user transaction center;
- buyer/seller transaction lifecycle with server-authoritative authorization, idempotency and notifications;
- Marketplace sidebar entry and shared in-plugin navigation;
- category/structured-field administration;
- listing image/attachment upload and cooked/lightbox rendering;
- `Marketplace::TradeContract` as the stable reputation integration seam plus the existing `marketplace-transaction-after-actions` outlet.

The 2026 Discourse-alignment refresh keeps those product/state-machine contracts unchanged while aligning the complete client surface with current Discourse guidance: plugin API integrations use `apiInitializer`; primary Marketplace actions use core `DButton` loading/disabled semantics; browse, listing forms, listing detail, favorites, storefront, offer flows and transaction flows expose consistent request/error states and stronger form/control accessibility; and shared responsive/accessibility styles normalize Marketplace surfaces without replacing their feature-specific BEM blocks. The existing route map and category administration remain intentionally intact where they already match current Discourse patterns.

The mobile-first presentation layer is loaded last and gives every Marketplace user and administration surface one responsive contract across phone and small-tablet widths. Browse/discovery, listing detail, create/edit, favorites, my listings, seller storefronts, offers, transactions, listing offer panels and category/structured-field administration share coordinated 800px/600px/430px breakpoints, safe-area spacing, touch-sized controls, horizontal navigation/filter rails, mobile card hierarchies, stacked actions and overflow protection while preserving desktop presentation and all server-authoritative product behavior.

Known intentional product boundaries remain: Marketplace does not process payments or provide escrow, shipping, auctions, paid boosts, or complex dispute arbitration unless explicitly added in a future scoped change.

Current source/tests and current GitHub state override this checkpoint if they ever disagree with it.
