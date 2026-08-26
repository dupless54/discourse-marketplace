# Marketplace V1 Architecture (Approved)

Status: approved for implementation. This is the authoritative design; implementation must
follow it. Corrections from review are incorporated inline (see §2, §7, §9, §12).

## 1. File / component layout

```
plugin.rb                                  metadata, enabled_site_setting, engine require, after_initialize
lib/marketplace/engine.rb                  isolated Rails engine, PLUGIN_NAME
lib/marketplace/guardian_extension.rb      all can_*? predicates
lib/marketplace/transaction_state_machine.rb   single source of truth for transitions
lib/marketplace/listing_status_sync.rb     listing status as a consequence of transaction status
lib/marketplace/listing_query.rb           browse/filter/paginate query object
lib/marketplace/trade_contract.rb          PUBLIC surface for Trade Reputation
config/routes.rb                           engine routes
config/settings.yml
config/locales/{server,client}.en.yml
db/migrate/*_create_marketplace_categories.rb
db/migrate/*_create_marketplace_listings.rb
db/migrate/*_create_marketplace_transactions.rb
app/models/marketplace/category.rb
app/models/marketplace/listing.rb
app/models/marketplace/transaction.rb
app/controllers/marketplace/{categories,listings,transactions}_controller.rb
app/serializers/marketplace/{category,listing,listing_detail,transaction}_serializer.rb
app/services/marketplace/listings/{create,update,transition_status}.rb
app/services/marketplace/transactions/{create,confirm,reject,cancel,dispute}.rb
app/jobs/regular/marketplace/notify_transaction_actors.rb
assets/javascripts/discourse/**            routes, components, api-initializer
assets/stylesheets/common/marketplace.scss
spec/**
docs/MARKETPLACE_ARCHITECTURE.md           this file
docs/TRADE_REPUTATION_CONTRACT.md          write once transactions stabilize
```

Namespacing: every Ruby class under `Marketplace::`, every table prefixed `marketplace_`,
every route under `/marketplace`, every setting prefixed `marketplace_`. Zero core monkey
patches; only `Guardian.prepend` inside a `reloadable_patch`.

## 2. Data model

### `marketplace_categories` (own table — not core categories)

Marketplace taxonomy is independent from forum discussion categories, so listings do not
reuse core `categories`. Kept intentionally minimal: no nesting, no per-category permission
system, no color/badge admin UI in V1.

| column | type | notes |
|---|---|---|
| `id` | bigserial | |
| `name` | varchar(100) NOT NULL | |
| `slug` | varchar(100) NOT NULL | url-safe, unique |
| `position` | integer NOT NULL DEFAULT 0 | manual sort order |
| `enabled` | boolean NOT NULL DEFAULT true | soft-disable instead of delete |
| `created_at` / `updated_at` | timestamptz NOT NULL | |

Indexes: unique on `slug`; `(enabled, position)` for the browse filter list. Managed via
plain site-admin CRUD (reuse existing admin route/plugin-admin patterns); no taxonomy
hierarchy, no permission matrix. `marketplace_listings.category_id` FK's to this table,
`ON DELETE RESTRICT` (disable, don't delete, a category with listings).

### `marketplace_listings`

| column | type | notes |
|---|---|---|
| `id` | bigserial | |
| `seller_id` | integer NOT NULL | always `current_user.id`, never client input |
| `title` | varchar(255) NOT NULL | |
| `raw` | text NOT NULL | markdown, cooked with `PrettyText.cook` |
| `cooked` | text NOT NULL | rendered server-side only |
| `category_id` | integer NOT NULL | FK -> `marketplace_categories.id` |
| `price_cents` | bigint NOT NULL | minor units only, never float/decimal-from-client |
| `currency` | varchar(3) NOT NULL | ISO 4217, validated against a setting-driven allowlist |
| `status` | integer NOT NULL DEFAULT 0 | |
| `published_at` | timestamptz NULL | first transition to active |
| `closed_at` | timestamptz NULL | sold/archived |
| `created_at` / `updated_at` | timestamptz NOT NULL | |

Status enum (integers with gaps, never rename/renumber): `draft=0, active=10, reserved=20,
sold=30, archived=40`.

Images/attachments: markdown uploads in `raw`, linked with
`UploadReference.ensure_exist!(upload_ids: extracted, target: listing)` — pending core
API verification (§12); no separate join table.

Indexes:
- `(status, category_id, created_at DESC)` — main browse
- partial `(category_id, created_at DESC) WHERE status = 10` — hot path stays small as
  sold/archived rows accumulate
- `(seller_id, status, created_at DESC)` — "my listings"
- `(status, currency, price_cents)` — price filter/sort
- GIN on `to_tsvector('simple', title || ' ' || coalesce(raw,''))` — V1 search; upgrade
  path is a `marketplace_listing_search_data` table if relevance tuning is ever needed
- CHECK `price_cents >= 0`, CHECK `char_length(title) BETWEEN 3 AND 255`

### `marketplace_transactions`

| column | type | notes |
|---|---|---|
| `id` | bigserial | |
| `listing_id` | integer NOT NULL | |
| `seller_id` | integer NOT NULL | denormalized at creation so the reputation record survives listing edits |
| `buyer_id` | integer NOT NULL | |
| `status` | integer NOT NULL DEFAULT 0 | |
| `initiated_by_id` | integer NOT NULL | V1 always seller; future-proofs buyer-initiated |
| `seller_confirmed_at` | timestamptz NULL | |
| `buyer_confirmed_at` | timestamptz NULL | |
| `completed_at` | timestamptz NULL | |
| `cancelled_at` / `cancelled_by_id` | timestamptz / integer NULL | |
| `disputed_at` / `disputed_by_id` | timestamptz / integer NULL | |
| `reason` | varchar(500) NULL | cancel/reject/dispute free text |
| `created_at` / `updated_at` | timestamptz NOT NULL | |

Status enum: `pending_confirmation=0, completed=10, cancelled=20, disputed=30`.

Integrity constraints — load-bearing:
- `CHECK (seller_id <> buyer_id)` — self-transaction blocked at the DB, not just in Ruby
- **`CREATE UNIQUE INDEX ... ON marketplace_transactions (listing_id) WHERE status IN
  (0, 10, 30)`** — at most one open-or-settled-or-disputed transaction per listing.
  `pending_confirmation`, `completed`, and `disputed` all block a new transaction on the
  same listing; only `cancelled` frees the listing for a future sale. This closes a gap
  in the original design: a disputed transaction must not be circumventable by starting a
  second transaction on the same listing while the dispute is unresolved.
- `CHECK (status <> 10 OR (completed_at IS NOT NULL AND seller_confirmed_at IS NOT NULL
  AND buyer_confirmed_at IS NOT NULL))` — a completed row is structurally provable
- FK on `listing_id` with `ON DELETE RESTRICT`; listings with transactions are archived,
  never destroyed

Indexes: `(buyer_id, status, created_at DESC)`, `(seller_id, status, created_at DESC)`,
`(status, completed_at DESC)` (reputation scans), `(listing_id)`.

No feedback table here. Trade Feedback is owned by the reputation plugin and keys off
`transaction_id`.

## 3. State machines

### Transaction (authoritative)

`lib/marketplace/transaction_state_machine.rb` holds one frozen hash:
`{from_status => {event => {to:, actor_roles:, timestamps:}}}`.

| from | event | actor | to |
|---|---|---|---|
| — | `create` | seller | `pending_confirmation` (sets `seller_confirmed_at`) |
| pending | `confirm` | buyer | `completed` (sets `buyer_confirmed_at`, `completed_at`) |
| pending | `reject` | buyer | `cancelled` |
| pending | `cancel` | seller, staff | `cancelled` |
| pending | `dispute` | buyer, seller, staff | `disputed` |
| completed | `dispute` | buyer, seller, staff | `disputed` |
| disputed | `cancel` / `complete` | staff only | `cancelled` / `completed` |
| cancelled | — | — | terminal |

Everything else raises `Marketplace::InvalidTransition` -> HTTP 422. Nothing outside this
file may write `status`; the model enforces this with a private writer.

### Listing (derived)

Listing status is never a source of truth; it is a projection of transaction status,
applied inside the same DB transaction by `Marketplace::ListingStatusSync.apply(transaction)`:

- transaction created -> listing `active` -> `reserved`
- transaction completed -> listing `reserved` -> `sold`, set `closed_at`
- transaction cancelled -> listing `reserved` -> `active` (only if no other
  open/settled/disputed transaction exists — consistent with the widened unique index)
- transaction disputed -> listing stays where it is

Seller-driven listing transitions (`draft->active`, `active->archived`, `sold->archived`)
go through `Listings::TransitionStatus` with its own allowed-transition map, refused while
an open (pending/completed/disputed, per §2) transaction exists.

## 4. Services

Discourse `Service::Base` objects (params contract -> model -> policy -> transaction with
steps) — exact DSL name pending core verification, §12. Invoked from controllers via
`with_service`.

`Transactions::Confirm` is the reference implementation of the concurrency rules; others
mirror it:

1. `model :transaction` -> row-locked (`FOR UPDATE`) fetch inside the DB transaction,
   before any read of `status`.
2. **Idempotency short-circuit:** if already in the target state and the acting user is
   the one recorded for it, return success with the existing record — a replayed confirm
   is a 200, not a 422 and not a second completion.
3. `policy :actor_may_perform` -> delegates to Guardian, which delegates role
   determination to the record (`transaction.role_for(user)`), never to params.
4. `policy :transition_allowed` -> state machine lookup.
5. `step :transition` -> compare-and-swap `UPDATE ... WHERE id = ? AND status =
   <expected>`; zero affected rows aborts the whole thing.
6. `step :sync_listing` -> `ListingStatusSync`, same DB transaction.
7. `step :publish_events` -> enqueue notification job + `DiscourseEvent.trigger` after
   commit, so nothing fires for a rolled-back transition.

Rescue `ActiveRecord::RecordNotUnique` on `Transactions::Create` and map it to a 409
("this listing already has an active or disputed sale"), not a 500.

## 5. Authorization / security

All predicates in `Marketplace::GuardianExtension`, prepended to `Guardian`:

- `can_create_marketplace_listing?` — logged in, not silenced/suspended, TL >=
  `marketplace_min_trust_level`
- `can_see_marketplace_listing?(l)` — `draft` visible to seller + staff only; others
  visible if `l.category.enabled?`
- `can_edit_marketplace_listing?(l)` — seller (while `draft`/`active`/`reserved`) or
  staff; price/category edits refused once a transaction is open
- `can_create_marketplace_transaction?(l)` — seller of `l`, `l.active?`, buyer is a real
  non-staged non-suspended user, `buyer != seller`
- `can_confirm/reject/cancel/dispute_marketplace_transaction?(t)` — role derived from
  `t.buyer_id`/`t.seller_id` vs `current_user.id`

Security posture:
- **Mass assignment:** service `params` contracts whitelist only `title, raw,
  category_id, price_cents, currency` (listing) and `listing_id, buyer_username, reason`
  (transaction). `seller_id`, `status`, and every `*_at` are structurally unreachable
  from params.
- **IDOR:** every `find` scoped through Guardian before serialization; 404 (not 403) for
  records the user cannot see.
- **Buyer identification** by `username`, resolved server-side to a `User`, rejecting
  staged/inactive/bot accounts.
- **Rate limits:** `RateLimiter` on listing create (per hour) and transaction create (per
  hour), plus a short-window limiter on confirm/reject to blunt replay storms.
- **No private data:** serializers emit `BasicUserSerializer` fields only; never emails,
  IPs, or trust-level internals. Reasons/dispute text visible to participants + staff only.
- Site setting `marketplace_enabled` defaults **false**.

## 6. API / serializer boundary

Engine mounted at `/marketplace`, all responses `.json`.

```
GET    /marketplace/categories
GET    /marketplace/listings            filters: category_id, status, currency,
                                        min_price, max_price, q, seller,
                                        order (created|price), page, limit(<=50)
POST   /marketplace/listings
GET    /marketplace/listings/:id
PUT    /marketplace/listings/:id
PUT    /marketplace/listings/:id/status         { status: "active" | "archived" }
GET    /marketplace/transactions        scope: mine|selling|buying, status, page
POST   /marketplace/transactions        { listing_id, buyer_username }
GET    /marketplace/transactions/:id
POST   /marketplace/transactions/:id/confirm
POST   /marketplace/transactions/:id/reject
POST   /marketplace/transactions/:id/cancel
POST   /marketplace/transactions/:id/dispute
```

Serializers:
- `CategorySerializer`: `id, name, slug, position`.
- `ListingSerializer` (index): `id, title, excerpt, category_id, price_cents, currency,
  status, thumbnail_url, created_at, seller` (BasicUser).
- `ListingDetailSerializer`: adds `cooked, can_edit, can_start_transaction,
  active_transaction_id`.
- `TransactionSerializer`: `id, listing_id, listing_title, seller, buyer, status,
  seller_confirmed_at, buyer_confirmed_at, completed_at, cancelled_at, disputed_at`, plus
  scope-derived `can_confirm, can_reject, can_cancel, can_dispute` and `viewer_role`
  (`"seller"|"buyer"|"staff"`).

N+1 control: `ListingQuery` always `includes(:seller, :category)` and preloads the
primary upload; transaction lists `includes(:seller, :buyer, :listing)`. Permission
booleans come from an already-loaded scope, never a per-row query. Pagination is offset +
`has_more` with a capped `limit`; keyset pagination is a documented follow-up if deep
paging becomes real.

## 7. Trade Reputation contract (the small public surface)

Two channels, both stable, neither exposing ActiveRecord:

**a) In-process module** `Marketplace::TradeContract` — `CONTRACT_VERSION = 1`, returns
an immutable value object:

```ruby
TransactionInfo = Data.define(:id, :listing_id, :seller_id, :buyer_id, :status, :completed_at)

TradeContract.find_transaction(id)                                  # -> TransactionInfo | nil
TradeContract.completed?(id)                                        # -> boolean
TradeContract.can_review?(reviewer_id:, reviewee_id:, transaction_id:)
TradeContract.completed_transaction_ids_for(user_id:, limit:, before_id:)
```

**Eligibility is defined exclusively here, explicitly, for V1:**

| transaction status | eligible for new feedback? |
|---|---|
| `completed` | yes |
| `pending_confirmation` | no |
| `cancelled` | no |
| `disputed` | no |

`can_review?` additionally requires: transaction exists, reviewer and reviewee are the
two distinct participants, reviewer is the counterpart of reviewee. This table is the
only place review eligibility is decided; the reputation plugin never re-derives it, and
a status added later must update this table explicitly rather than falling through to a
default.

**b) DiscourseEvents** with a frozen payload (a `TransactionInfo`, not the AR record):
`marketplace_transaction_created`, `_completed`, `_cancelled`, `_disputed`.

**Hard boundary:** Marketplace exposes eligibility/state only through `TradeContract` and
these events. It never reads, writes, modifies, or deletes any table owned by the Trade
Reputation plugin (feedback rows included) — reputation data lifecycle is entirely
outside Marketplace's responsibility, including on listing/transaction deletion paths.
Reputation may reference `transaction_id` and call `TradeContract` methods; it may not
query `marketplace_transactions`/`marketplace_listings` directly or import
`Marketplace::Transaction`/`Marketplace::Listing`. Documented in full in
`docs/TRADE_REPUTATION_CONTRACT.md` once transactions stabilize.

## 8. Notifications

One job, `Jobs::Marketplace::NotifyTransactionActors`, enqueued after commit, for:
confirmation requested (-> buyer), buyer confirmed (-> seller), buyer rejected /
cancelled / disputed (-> counterpart), completed (-> both). Exact registration mechanism
pending core verification, §12.

## 9. Tests

- **Model:** enum integrity; `seller_id <> buyer_id` CHECK; the partial unique index
  covering `pending_confirmation`/`completed`/`disputed` (insert a second transaction
  while the first is in any of those three states -> `RecordNotUnique`; insert after
  `cancelled` -> succeeds); completed-row CHECK; `marketplace_categories` slug uniqueness.
- **State machine:** table-driven — every (from, event, actor role) pair, asserting
  allowed -> new status + timestamps, disallowed -> `InvalidTransition`.
- **Services:** happy path per transition; idempotent replay of `confirm` returns the
  same record and does not re-fire notifications; concurrency spec — two threads
  confirming the same transaction, exactly one wins; `Transactions::Create` against a
  listing with an existing disputed transaction is rejected (409).
- **Request specs:** anonymous -> 403; non-participant confirm -> 403/404; seller
  confirming their own sale -> 422; posting `seller_id`/`status`/`completed_at` in params
  has zero effect; listing in a disabled category -> 404; rate limiter trips.
- **Contract spec:** `can_review?` matrix over all four transaction statuses x
  (participant/non-participant/self-review); confirms `disputed` and `cancelled` are
  never eligible; events fire once with the right payload; `TradeContract` never returns
  an AR object; verify no code path in Marketplace touches a reputation-owned table.
- **Query spec:** filter/sort correctness plus an N+1 assertion on the index endpoints.
- **System spec (2, minimal):** create + publish a listing; seller starts sale -> buyer
  confirms -> listing shows sold.
- Fabricators in `spec/fabricators/marketplace_fabricator.rb`.

## 10. Frontend

`assets/javascripts/discourse/`:
- Routes: `marketplace` (parent), `listings/index`, `listings/new`, `listings/show`,
  `listings/edit`, `transactions/index`, `transactions/show`.
- Glimmer components under `components/marketplace/`: `listing-card`, `listing-list`,
  `listing-filters`, `listing-form`, `transaction-panel`, `transaction-actions`,
  `start-sale-modal` (username chooser via core `user-chooser`).
- Data via `discourse/lib/ajax` + `@tracked` state; skip the store/adapter layer for V1.
- `api-initializers/marketplace.js` adds a sidebar link and a user-menu badge for
  pending confirmations — additive plugin APIs only, no core template overrides, no
  widget patching.
- Never render `raw`; render server-`cooked` HTML only. Price displayed via
  `Intl.NumberFormat(currency)` from `price_cents`.
- Action buttons enabled from serializer `can_*` booleans; every action re-authorized
  server-side regardless.

## 11. Risks and compatibility

- Greenfield: no data migration risk, but the two enums and the contract are permanent.
  Use integers with gaps, add `CONTRACT_VERSION`, never renumber.
- Marketplace categories are a separate, deliberately minimal table — no nesting,
  permissions, or admin complexity in V1; a richer taxonomy is a documented future option,
  not a default to build toward now.
- Listing deletion: `ON DELETE RESTRICT` from transactions; category deletion is
  disallowed once listings reference it — disable a category instead. Handle account
  deletion by archiving listings, never deleting transactions (reputation history must
  survive account changes).
- Deep pagination with offset degrades past a few thousand pages; acceptable at V1 scale,
  flagged for keyset upgrade.
- Dispute path is deliberately thin (a flag + staff resolve); the state machine already
  has the `disputed` node so richer arbitration later needs no migration.

## 12. Required core-version verification before implementation

Do not assume unsupported API names. Verify against the installed/target Discourse core
version before writing code:

1. `Service::Base` DSL — confirm `params do ... end` vs `contract do ... end`, and the
   exact `policy`/`step`/`model` block names in that core version.
2. Notification registration API — confirm whether plugin-registrable notification types
   and `register_notification_consolidation_plan` exist as designed in §8; if not, the
   documented fallback is `SystemMessage`/`PostCreator` private messages.
3. `UploadReference` / upload-attachment API — confirm `ensure_exist!` signature and
   availability as used in §2.
4. Plugin route/engine mounting conventions — confirm the isolated-engine + `plugin.rb`
   `add_admin_route`/asset-registration patterns current in that core version.

None of §1–§11 should be implemented against an assumed API name for these four items;
confirm first, then proceed.
