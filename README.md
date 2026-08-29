<p align="center">
  <a href="https://buymeacoffee.com/erespawn">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" width="217" height="60">
  </a>
</p>

# Discourse Marketplace

A native Discourse marketplace for member listings, buyer/seller transactions, negotiated offers, favorites, seller storefronts, and structured category-driven commerce.

The plugin keeps listing and transaction authority on the server and exposes a small versioned integration seam for companion plugins such as [`discourse-trade-reputation`](https://github.com/dupless54/discourse-trade-reputation).

## Current Features

- Listing create, edit, publish, archive, and browse flows.
- Search, sorting, category filtering, and server-authoritative visibility rules.
- **My Listings** management experience.
- Listing image/attachment uploads and Discourse-compatible lightbox presentation.
- Category badges and improved listing-card/detail hierarchy.
- Admin-managed categories and safe deletion of unused categories.
- Category-specific structured fields: text, textarea, integer, boolean, and select.
- Category-driven dynamic browse filters generated from enabled structured field definitions.
- Responsive native Discourse navigation with a Marketplace sidebar entry and shared internal navigation.
- English and Turkish localization.

## Inventory and Listing Lifetime

Listings support server-authoritative inventory/lifetime semantics:

- `single`
- `finite`
- `unlimited`
- stock quantity / reserved / sold tracking
- optional listing expiration

The transaction layer revalidates availability and stock constraints instead of trusting browser state.

## Transactions

- Buyer/seller transaction state machine with participant/staff authorization.
- Immutable transaction snapshots for listing title, price, and currency at transaction creation time.
- Participant-scoped **Transaction Center** at `/marketplace/transactions`.
- Buyer/seller views, status filters, pagination, confirm/cancel actions, and exact transaction navigation.
- Notifications for transaction creation, first confirmation, completion, and cancellation.
- Pending-only uniqueness rules that allow valid concurrent buyers for finite/unlimited inventory.

## Marketplace V2 Highlights

The current `main` branch includes the merged V2 feature work:

### Favorites

- Persistent per-user listing favorites.
- Idempotent favorite/unfavorite behavior.
- Dedicated `/marketplace/favorites` page.
- Viewer-specific favorite state on browse/detail surfaces without N+1 lookups.

### Offers and Counteroffers

- Buyer offers and seller/buyer counteroffers.
- Accept, reject, withdraw, and expiry lifecycle.
- Atomic conversion of accepted offers into normal Marketplace transactions.
- Negotiated price captured in the immutable transaction snapshot without changing the listing's asking price.
- Offer notifications and a dedicated My Offers experience.

### Dynamic Category Filters

- Filters are generated from the selected category's enabled structured field definitions.
- Integer ranges and validated select/boolean/text filters are processed server-side.
- Unknown, disabled, or malformed filters fail closed instead of being interpreted by the client.

### Seller Storefronts

- Public username-based seller storefronts.
- Core Discourse profile-visibility rules are reused.
- Only currently browseable listings are shown.
- Draft, expired, unavailable, or disabled-category listings remain hidden.

## Main Routes

- `/marketplace` — browse listings
- `/marketplace/new` — create a listing
- `/marketplace/mine` — My Listings
- `/marketplace/transactions` — Transaction Center
- `/marketplace/favorites` — Favorites

Additional listing detail/edit, offer, and seller-storefront routes are handled inside the Marketplace engine.

## Trade Reputation Integration

`Marketplace::TradeContract` is the versioned public boundary used by Trade Reputation. Marketplace owns listing/transaction truth; reputation plugins should not query Marketplace internal tables or private services directly.

A generic `marketplace-transaction-after-actions` plugin outlet is available for transaction-related companion UI such as the Trade Reputation feedback CTA.

## Security and Data Integrity

Important invariants include:

- listing seller identity is derived from the authenticated user;
- sellers cannot buy their own listings;
- listing state and transaction state are separate;
- only transaction participants and authorized staff may act on a transaction;
- invalid state transitions fail server-side;
- completion/cancellation and other replay-sensitive actions are designed to be idempotent;
- DB constraints/indexes protect important uniqueness and query paths;
- private data and internal identifiers are not intentionally exposed through public listing APIs.

## Installation

Add the plugin to your Discourse container configuration:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/dupless54/discourse-marketplace.git
```

Rebuild Discourse:

```bash
cd /var/discourse
./launcher rebuild app
```

Enable `marketplace_enabled` in site settings after the rebuild.

## Development

The repository uses official Discourse Plugin CI and exact-scope delivery rules. Current source/tests are authoritative; architecture details are documented in `docs/MARKETPLACE_ARCHITECTURE.md` and repository development rules start in [`AGENTS.md`](AGENTS.md).

## Support

If Marketplace is useful to your community, you can support continued development through the Buy Me a Coffee banner at the top of this README.
