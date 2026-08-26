# Marketplace V1 Architecture (Approved)

Status: approved, reflects the merged implementation as of `cc4fd43` on `main`. Sections
§2, §3, §4, §6, §7, §9, and §11 were corrected in Phase 2A after Transactions stabilized;
earlier drafts of those sections described a seller-initiated, dispute-capable design that
was never built. Phase 2B (this revision) implemented the transaction completion event; §4,
§7, §9, §11, and §12 were updated accordingly. This document is authoritative; where it and
the code ever disagree, treat that as a bug in the document and fix the document, not the
code, unless a real behavior change is intended.

## 1. File / component layout

```
plugin.rb                                  metadata, enabled_site_setting, engine require, after_initialize
lib/marketplace/engine.rb                  isolated Rails engine, PLUGIN_NAME
lib/marketplace/guardian_extension.rb      all can_*? predicates
lib/marketplace/listing_query.rb           browse/filter/paginate query object
lib/marketplace/transaction_invariant_violation.rb   raised on a failed CAS/shape invariant
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
app/services/marketplace/transactions/{create,confirm,cancel}.rb
assets/javascripts/discourse/**            not yet implemented (see §10)
assets/stylesheets/common/marketplace.scss not yet implemented
spec/**
docs/MARKETPLACE_ARCHITECTURE.md           this file
docs/TRADE_REPUTATION_CONTRACT.md          write once the contract's consumer (Trade
                                            Reputation) is ready to integrate against it
```

Namespacing: every Ruby class under `Marketplace::`, every table prefixed `marketplace_`,
every route under `/marketplace`, every setting prefixed `marketplace_`. Zero core monkey
patches; only `Guardian.prepend` inside a `reloadable_patch`.

There is no `transaction_state_machine.rb` or `listing_status_sync.rb` — the state
transitions are implemented directly inside each `Transactions::*` service (see §3, §4),
not extracted into a separate frozen-hash state-machine object or a standalone listing-sync
class. `Transactions::Reject` and `Transactions::Dispute` do not exist; there is no dispute
concept in this implementation (see §3).

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
plain site-admin CRUD; no taxonomy hierarchy, no permission matrix. `marketplace_listings.
category_id` FK's to this table, `ON DELETE RESTRICT` (disable, don't delete, a category
with listings).

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
| `created_at` / `updated_at` | timestamptz NOT NULL | |

Status enum (integers with gaps, never rename/renumber): `draft=0, active=10, reserved=20,
sold=30, archived=40`.

### `marketplace_transactions`

Real, merged schema (`db/migrate/20260826034000_create_marketplace_transactions.rb`):

| column | type | notes |
|---|---|---|
| `id` | bigserial | |
| `listing_id` | bigint NOT NULL | FK -> `marketplace_listings.id`, `ON DELETE RESTRICT` |
| `buyer_id` | integer NOT NULL | always `current_user.id` at creation, never client input |
| `seller_id` | integer NOT NULL | captured from `listing.seller_id` at creation |
| `status` | integer NOT NULL DEFAULT 0 | |
| `buyer_confirmed_at` | timestamptz NULL | |
| `seller_confirmed_at` | timestamptz NULL | |
| `completed_at` | timestamptz NULL | |
| `cancelled_at` | timestamptz NULL | |
| `cancelled_by_id` | integer NULL | participant or staff who cancelled |
| `created_at` / `updated_at` | timestamptz NOT NULL | |

Status enum: `pending=0, completed=10, cancelled=20`. There is no `disputed` status and no
`initiated_by_id`, `reason`, `disputed_at`, or `disputed_by_id` column — none of these were
built; do not design against them.

Integrity constraints — load-bearing, all enforced at the database, not just in Ruby:
- `marketplace_transactions_buyer_seller_check`: `CHECK (buyer_id <> seller_id)` — a
  self-transaction is rejected by the database even if model validation is bypassed.
- `marketplace_transactions_status_check`: `CHECK (status IN (0, 10, 20))`.
- `idx_marketplace_transactions_listing_open`: **`UNIQUE (listing_id) WHERE status <> 20`**
  — at most one non-cancelled (pending or completed) transaction per listing at a time.
  Cancelling is the only way to free a listing for a new transaction; a completed
  transaction permanently blocks a second one on the same listing (the listing itself also
  moves to `sold`, so this is redundant-but-defense-in-depth with the listing status).
- `marketplace_transactions_status_shape_check`: a single CHECK enforcing that each status
  can only ever be persisted with its complete, correct set of fields:
  - `pending`: `completed_at`, `cancelled_at`, `cancelled_by_id` all NULL; not both
    confirmation timestamps present at once (that combination only exists transiently in
    memory during the final `confirm`, in the same `save!` that also flips `status` and
    sets `completed_at` — see §4).
  - `completed`: `completed_at`, `buyer_confirmed_at`, and `seller_confirmed_at` all
    present; `cancelled_at`/`cancelled_by_id` NULL.
  - `cancelled`: `cancelled_at` and `cancelled_by_id` present; `completed_at` NULL. Prior
    confirmation timestamps (0 or 1 of them) are left untouched as audit history.

Indexes actually present: only the partial unique index above (plus the implicit primary
key on `id`). **There is no index on `buyer_id`, `seller_id`, or `completed_at` alone.**
Earlier drafts of this document assumed `(buyer_id, status, created_at DESC)`,
`(seller_id, status, created_at DESC)`, and `(status, completed_at DESC)` — none of these
were migrated. Any future "my transactions" listing endpoint (§6) or a Trade Reputation
scan over completed transactions will need one of these added first; tracked in §11.

No feedback table here. Trade Feedback is owned by the reputation plugin and keys off
`transaction_id` via `Marketplace::TradeContract` (§7) only — never a direct reference to
this table.

## 3. Transaction lifecycle (authoritative — matches `Marketplace::Transaction` +
`Transactions::{Create,Confirm,Cancel}`)

There is no separate state-machine object; the transition rules live directly in the three
services below, and the DB shape CHECK (§2) is what actually makes an invalid persisted
state impossible, not a Ruby-level table lookup.

```
                 buyer creates
   (none)  ─────────────────────────►  pending
                                       (listing: active -> reserved)

   pending ──── either participant confirms first ────►  pending
                (that participant's *_confirmed_at set; status unchanged)

   pending ──── the OTHER participant then confirms ────►  completed
                (both confirmed_at + completed_at set together, single save;
                 listing: reserved -> sold; completion event fires after commit — §7)

   pending ──── buyer, seller, or staff cancels ────►  cancelled
                (listing: reserved -> active)

   completed, cancelled: terminal — no further transitions from either.
```

Key rules:
- **Buyer-initiated.** `Transactions::Create` is called by the buyer, never the seller;
  the seller is derived from `listing.seller`, never from client input. A seller cannot
  create a transaction against their own listing (`Guardian#can_create_marketplace_
  transaction?` rejects it).
- **Symmetric dual confirmation.** Either the buyer or the seller may confirm first;
  whichever one does not change `status`. Only the second, *opposite*, confirmation
  transitions `pending -> completed`, and it does so by setting both confirmation
  timestamps, `status`, and `completed_at` together in one `save!` — there is never an
  intermediate persisted row with both timestamps set but still `pending`.
- **Replay is idempotent, not an error.** Confirming an already-completed transaction (by
  either participant) re-returns the existing record with a 200, not a 422. Confirming a
  second time after already having confirmed once (before the other side has) is also a
  no-op success. Cancelling an already-cancelled transaction is likewise a safe replay.
  Confirming a cancelled transaction, or cancelling a completed one, is rejected
  (`transaction_not_confirmable` / `transaction_not_cancellable`, HTTP 422) — cancelled and
  completed are each terminal from the other's perspective.
- **Cancellation.** Either participant may cancel while `pending`; staff may also cancel as
  a moderation override. Nobody — including staff — may cancel a `completed` transaction;
  completion is final.
- **Concurrency.** `Confirm` and `Cancel` row-lock (`FOR UPDATE`) both the transaction and
  its listing before reading status, inside one DB transaction, so two concurrent
  confirmations or a confirm racing a cancel resolve deterministically. `Create` locks the
  listing and additionally has a DB unique-index backstop (`ActiveRecord::RecordNotUnique`
  rescued and mapped to a stable `listing_unavailable` marker) in case two buyers race past
  the lock.
- **No dispute state.** There is no `disputed` status, no dispute transition, and no
  `Transactions::Dispute` service. If arbitration is ever needed it is a genuinely new
  feature, not something already partially built here.

## 4. Services

Discourse `Service::Base` objects (`params` -> `model` -> `policy` -> `transaction do ...
end` containing `step`s) — confirmed against the installed core (`lib/service/base/
steps_helpers.rb`). `transaction do ... end` wraps only its own nested steps in
`ActiveRecord::Base.transaction { }`; a step placed after that block in a service's
top-level DSL only runs once the block returns, i.e., after commit. `Confirm` does not use
this pattern for its completion event — see §7 for why, and for the `DB.after_commit`
mechanism it uses instead.

- **`Transactions::Create`**: locks the listing; if a pending transaction already exists
  for the current buyer, replays it; if one exists for a *different* buyer (or a DB
  unique-index collision occurs), fails with a stable `listing_unavailable` marker rather
  than a raw 500; otherwise authorizes, builds, saves the transaction, and CAS's the
  listing `active -> reserved`, only exposing the new record as the service's public result
  once both the save and the CAS have succeeded.
- **`Transactions::Confirm`**: locks the transaction and listing; branches on current
  status (cancelled -> reject, completed -> replay, pending -> determine which participant
  is acting and whether they or the other side already confirmed) to decide between a
  first-confirmation save, a final-confirmation save-plus-listing-CAS, or a no-op replay.
  The final-confirmation branch (`complete_transaction_and_listing`) additionally registers
  the completion event, as its very last step, only once the listing CAS has been verified
  to affect exactly one row — see §7.
- **`Transactions::Cancel`**: locks the transaction and listing; branches similarly
  (cancelled -> replay, completed -> reject, pending -> cancel-and-release).

All three raise `Marketplace::TransactionInvariantViolation` (mapped to HTTP 409) if an
internal CAS ever affects zero rows — a defensive backstop behind the row locks, not the
primary concurrency mechanism.

Params contracts are the mass-assignment boundary: `Transactions::Create` accepts only
`listing_id`; `Transactions::Confirm` and `Transactions::Cancel` accept only
`transaction_id` (from the route, not the body). There is no `buyer_username` or `reason`
parameter — the buyer is always `guardian.user`, and there is no free-text reason field on
the model.

## 5. Authorization / security

All predicates in `Marketplace::GuardianExtension`, prepended to `Guardian`:

- `can_create_marketplace_listing?` — logged in, not silenced/suspended, TL >=
  `marketplace_min_trust_level`.
- `can_see_marketplace_listing?(l)` — `draft` visible to seller + staff only; others
  visible if `l.category.enabled?`.
- `can_edit_marketplace_listing?(l)` — seller (while `draft`/`active`) or staff.
- `can_create_marketplace_transaction?(l)` — authenticated, not silenced/suspended, `l`
  must be `active` with an enabled category, and the acting user must not be `l.seller`.
- `can_see_marketplace_transaction?(t)` — staff, or either participant.
- `can_confirm_marketplace_transaction?(t)` — authenticated, not silenced/suspended, and
  either participant; not staff-overridable (staff cannot confirm on someone's behalf).
- `can_cancel_marketplace_transaction?(t)` — either participant, or staff (moderation
  override). None of these predicates depend on the transaction's current status — the
  services themselves reject invalid-state actions (§3), Guardian only answers "is this
  actor allowed to attempt this kind of action at all."

There is no `can_reject_marketplace_transaction?` or `can_dispute_marketplace_transaction?`
— those actions don't exist.

Security posture:
- **Mass assignment:** see §4 — params contracts whitelist exactly `listing_id` /
  `transaction_id`; `seller_id`, `buyer_id`, `status`, and every `*_at` are structurally
  unreachable from client params.
- **IDOR:** every `find` scoped through Guardian before serialization; 404 (not 403) for
  records the user cannot see or act on where the controller uses `on_model_not_found`
  and `on_failed_policy { raise Discourse::NotFound }`.
- **No private data:** `TransactionSerializer` emits ids and timestamps only — no emails,
  IPs, or trust-level internals.
- Site setting `marketplace_enabled` defaults **false**.

## 6. API / serializer boundary

Engine mounted at `/marketplace`, all responses `.json`. Routes actually defined
(`config/routes.rb`):

```
GET    /marketplace/categories

GET    /marketplace/listings            filters per ListingQuery (see lib/marketplace/listing_query.rb)
POST   /marketplace/listings
GET    /marketplace/listings/:id
PUT    /marketplace/listings/:id
PUT    /marketplace/listings/:id/status

POST   /marketplace/transactions        { listing_id }
GET    /marketplace/transactions/:id
POST   /marketplace/transactions/:id/confirm
POST   /marketplace/transactions/:id/cancel
```

There is no `POST .../reject`, `POST .../dispute`, or `GET /marketplace/transactions`
index/list route yet — a "my transactions" listing endpoint is a plausible future addition
(would need the indexes noted in §2/§11 first) but is not built.

`TransactionSerializer` (`app/serializers/marketplace/transaction_serializer.rb`) emits:
`id, listing_id, buyer_id, seller_id, status, buyer_confirmed_at, seller_confirmed_at,
completed_at, cancelled_at, cancelled_by_id, created_at, updated_at`. It does not currently
emit nested `seller`/`buyer`/`listing` objects, `viewer_role`, or `can_confirm`/`can_cancel`
booleans — those are plausible future serializer additions, not present today.

## 7. Trade Reputation contract (the small public surface)

**`Marketplace::TradeContract`** (`lib/marketplace/trade_contract.rb`), `VERSION = 1`,
exposes exactly one public lookup and one immutable value type:

```ruby
TransactionInfo = Data.define(:transaction_id, :buyer_id, :seller_id, :completed_at)

TradeContract.completed_transaction_info(transaction_id)   # -> TransactionInfo | nil
```

The method name intentionally encodes eligibility, and is the *only* public lookup — there
is deliberately no generic `find_transaction`, `transaction_info`, or `completed?` API.
This makes "Reputation accidentally treats a pending/cancelled trade as feedback-eligible"
a naming-impossible bug class rather than a rule someone has to remember:

| transaction status | `completed_transaction_info` result |
|---|---|
| unknown id | `nil` |
| `pending` | `nil` |
| `cancelled` | `nil` |
| `completed` | populated `TransactionInfo` |

Input handling: only an actual `Integer` (not a numeric string, not `nil`, not a float) is
accepted; anything else, and any non-positive integer, returns `nil` without raising. The
contract never leaks an `ActiveRecord::RecordNotFound` or any other Marketplace-internal
exception across the plugin boundary.

`TransactionInfo` intentionally omits `listing_id` (no current feedback-eligibility rule
needs it) and `status` (the method name already encodes "completed"; a redundant status
field would just invite a second, unnecessary check). It never carries confirmation
timestamps, cancellation metadata, a `User`, a `Listing`, or the `Marketplace::Transaction`
AR object itself — only four scalar/time fields, freshly queried and copied on every call,
so a caller mutating a `Transaction` they hold elsewhere in memory cannot affect a
previously returned `TransactionInfo`, and a caller holding a `TransactionInfo` has no way
to write back to Marketplace state (it is a `Data` object: no setters, no `save`/`update`).

**Hard boundary**, unchanged from Phase 1 and still the load-bearing rule for everything
above: Trade Reputation may call `TradeContract` methods and reference `transaction_id`, and
nothing else. It may not query `marketplace_transactions`/`marketplace_listings`, `belongs_
to` a Marketplace model, share Marketplace's service context, or otherwise import
`Marketplace::Transaction`/`Marketplace::Listing`. Marketplace, symmetrically, never reads,
writes, or references any table owned by Trade Reputation. Full contract text lives in
`docs/TRADE_REPUTATION_CONTRACT.md` once Trade Reputation exists to consume it.

**Completion event (Phase 2B, implemented).** `:marketplace_transaction_completed` fires
exactly once per real `pending -> completed` transition, and zero times for transaction
creation, first confirmation, a same-side duplicate confirmation while pending, completed
replay, a confirm attempt on a cancelled transaction, cancellation, cancelled replay, or a
failed completion that rolls back (including a listing CAS invariant failure). The payload
is a single scalar `Integer` — the `transaction_id` — never a `Marketplace::Transaction`,
`Marketplace::Listing`, or `TradeContract::TransactionInfo`; a consumer that needs more
calls `TradeContract.completed_transaction_info(transaction_id)`.

Implementation, inside `Transactions::Confirm#complete_transaction_and_listing`, as the last
statement, only after the listing CAS is verified to have affected exactly one row:

```ruby
transaction_id = transaction_record.id
DB.after_commit do
  DiscourseEvent.trigger(:marketplace_transaction_completed, transaction_id, continue_on_error: true)
end
```

`DB.after_commit` (`lib/mini_sql_multisite_connection.rb` in core) was chosen over a
top-level post-`transaction do...end` `Service::Base` step because its safety is proven by
the framework itself rather than by an assumption about `Confirm`'s call graph: core's own
spec suite (`spec/lib/mini_sql_multisite_connection_spec.rb`) proves it fires only after the
*true outermost* transaction commits (correct even under future `requires_new` nesting, e.g.
if `Confirm` were ever called from inside another service's transaction), never fires if
that transaction rolls back, and runs immediately if no transaction is open at all. A
top-level DSL step, by contrast, would only be safe for as long as `Confirm` happens to
remain the outermost transaction for every caller — an assumption a future refactor (e.g. a
bulk-confirm admin action wrapping several `Confirm` calls in one transaction) could
silently violate. `DB.after_commit` itself provides no exception isolation for its callback
(`AfterCommitWrapper#committed!` has no rescue), so `continue_on_error: true` on the
`DiscourseEvent.trigger` call remains mandatory regardless of delivery mechanism — without
it, a raising listener would propagate back into the request and could turn an
already-committed, successful confirmation into a client-visible failure.

**Delivery is best-effort, not durable, and never authoritative.** `DB.after_commit` gives
ordering and rollback-safety guarantees, not delivery guarantees: if the process crashes
after Postgres commits but before the Ruby callback runs, the event is lost silently, with
no retry and no outbox. This is why feedback eligibility must always be revalidated through
`TradeContract.completed_transaction_info` at submission time, specifically so that
transactions completed before Trade Reputation was installed, while it was disabled, before
any listener was loaded, or during a lost-event window remain reviewable without requiring
an event to have ever fired for them. The event exists only for optional uses — notifications,
cache invalidation, async processing — never for correctness.

## 8. Notifications

Not yet implemented. A future `Jobs::Marketplace::NotifyTransactionActors`, enqueued after
commit, is a plausible design for: first confirmation received (-> the other participant),
completion (-> both). Exact registration mechanism still pending core verification; no
`app/jobs` directory exists in this plugin yet.

## 9. Tests

Reflects the specs that actually exist under `spec/`:

- **Model** (`spec/models/marketplace/transaction_spec.rb`): enum exactness
  (`pending=0/completed=10/cancelled=20`); `buyer_id <> seller_id` at both the model and
  DB-CHECK level; the full status-shape CHECK for all three statuses (each required field
  present/absent combination); the partial unique index on `listing_id` (second non-
  cancelled transaction on the same listing -> `RecordNotUnique`; allowed again once the
  first is cancelled).
- **Guardian** (`spec/lib/marketplace/guardian_extension_spec.rb`): every `can_*?`
  predicate x (anonymous / non-participant / participant / staff), including that
  eligibility to confirm/cancel does not depend on current transaction status (that's the
  services' job, not Guardian's).
- **Services** (`spec/services/marketplace/transactions/{create,confirm,cancel}_spec.rb`):
  happy path per transition; idempotent replay behavior (completed replay, cancelled
  replay, first-confirmation-then-same-actor-again); rejecting confirm-on-cancelled and
  cancel-on-completed; the `listing_unavailable` contention path in `Create`.
  `confirm_spec.rb`'s `"completion event"` group (Phase 2B) additionally proves: zero events
  on first confirmation, same-side pending replay, completed replay, a cancelled-transaction
  confirm attempt, and a forced listing-CAS failure/rollback; exactly one event, with the
  exact scalar `transaction.id` payload (never the AR object), on the real final
  confirmation; the listener observes already-committed state via
  `TradeContract.completed_transaction_info`; a raising listener does not turn a successful
  `Confirm` result into a failure; and `continue_on_error: true` is the exact argument
  passed to `DiscourseEvent.trigger`.
- **Requests** (`spec/requests/marketplace/transactions_controller_spec.rb`): anonymous ->
  401/403; non-participant -> 404; mass-assignment attempts on `seller_id`/`status`/
  `completed_at` have zero effect.
- **TradeContract** (`spec/lib/marketplace/trade_contract_spec.rb`, added Phase 2A): the
  full input matrix (nil, zero, negative, non-integer string, numeric string, unknown
  positive id, pending, cancelled) all -> `nil`; a completed transaction returns exact
  `transaction_id`/`buyer_id`/`seller_id`/`completed_at`; no `listing_id`/`status` exposed;
  no AR object or AR-like mutability (`save`/`save!`/`update`/`update!` absent, no field
  setters); a `TransactionInfo` already returned is unaffected by later in-memory mutation
  of the underlying `Transaction`; exactly one public singleton method exists; `VERSION ==
  1`.
- **Query** (`spec/lib/marketplace/listing_query_spec.rb`): filter/sort correctness.

## 10. Frontend

Not yet implemented — no `assets/javascripts/discourse/` directory exists. The routes,
Glimmer components, and `api-initializers/marketplace.js` sketched in earlier drafts of
this document remain a reasonable target shape for that future work but should be verified
against current core frontend conventions when it's actually started, not assumed from this
document.

## 11. Risks and compatibility

- **Missing supporting indexes (new, Phase 2A).** `marketplace_transactions` has only the
  one partial unique index (§2) — no index on `buyer_id`, `seller_id`, or `completed_at`.
  A future "my transactions" endpoint (§6) or a Trade Reputation scan over completed
  transactions (should one ever be added — `TradeContract` itself is point-lookup-only and
  doesn't need this) will need a migration adding at least `(buyer_id, status)` and
  `(seller_id, status)` before shipping, per CLAUDE.md's N+1/indexing guidance. Still
  flagged, not fixed — Phase 2B only touches `Confirm`, its spec, and this document.
- **Completion event delivery is best-effort (Phase 2B).** `DB.after_commit` proves
  ordering (fires only after the true outermost commit) and rollback-safety (never fires on
  rollback, per core's own `mini_sql_multisite_connection_spec.rb`), but not delivery
  durability — a process crash between DB commit and callback execution silently loses the
  event, with no outbox or retry. This is an accepted, permanent property of the design, not
  a gap to close later: see §7 for why `TradeContract` remains the correctness boundary
  regardless.
- Greenfield: no data migration risk, but the two enums (`Listing#status`, `Transaction#
  status`) and `TradeContract::VERSION` are permanent once Trade Reputation exists as a
  consumer. Use integers with gaps, never renumber.
- Marketplace categories are a separate, deliberately minimal table — no nesting,
  permissions, or admin complexity in V1.
- Listing deletion: `ON DELETE RESTRICT` from transactions; category deletion is
  disallowed once listings reference it — disable a category instead.
- No dispute path exists (§3). If arbitration is ever required, it is new design work, not
  an extension of anything half-built here.

## 12. Required core-version verification before further implementation

Confirmed during Phase 1/2A/2B review, against the installed core:

1. `Service::Base` DSL — confirmed: `params do ... end`, `model`, `policy`, `step`,
   `transaction do ... end` (`lib/service/base/steps_helpers.rb`), as already used by every
   `Transactions::*`/`Listings::*` service.
2. `DiscourseEvent.trigger`/`.on`/`.off` (`lib/discourse_event.rb`) — confirmed synchronous,
   in-process, `continue_on_error: false` by default; with `continue_on_error: true`, a
   raising listener is logged (`Discourse.warn_exception`) and does not block later
   listeners for the same event.
3. `DB.after_commit` (`lib/mini_sql_multisite_connection.rb`) — confirmed against its own
   core spec suite: runs immediately outside any transaction; deferred and fired only after
   a real commit; suppressed entirely on rollback; waits for the true outermost commit under
   nested/`requires_new` transactions rather than firing at an inner savepoint release; and
   provides no exception isolation of its own (the mandatory mitigation is
   `continue_on_error: true` on the `DiscourseEvent.trigger` call inside the block, not
   anything `DB.after_commit` does for us). Discourse's own test harness
   (`spec/support/test_setup.rb`'s `DB.test_transaction = ...`) makes this fully observable
   from ordinary service specs, not just request/integration specs.
4. Cross-plugin soft-dependency convention — confirmed: no declarative "requires plugin X"
   manifest exists anywhere in core; the established idiom is a runtime `defined?(::Some
   Namespace)` check (only real example found: a spec in `discourse-github` checking
   `defined?(::Chat)`). Trade Reputation, when it exists, should guard on `defined?(::
   Marketplace::TradeContract)` plus a `TradeContract::VERSION` check, not a manifest field.

Still unverified, and not yet needed (no code in this plugin depends on them yet):
notification registration API (§8) and `UploadReference`/upload-attachment API for listing
images — confirm before starting §8/§10 work, not before this document's own accuracy.
