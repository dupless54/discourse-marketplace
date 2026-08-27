# Marketplace V1 Architecture (Approved)

Status: approved. **Marketplace V1 is COMPLETE** on `main`
(`a3f44a845629a51d5ceb04696332740a60ebd295`): every area in `docs/PROJECT_BRIEF.md` --
listings, transactions/lifecycle, notifications, browse/search/filter, My Listings,
categories/admin, image/attachment upload, and the `Marketplace::TradeContract` integration
surface -- is implemented and merged. Sections §2, §3, §4, §6, §7, §9, and §11 were corrected
in Phase 2A after Transactions stabilized; earlier drafts of those sections described a
seller-initiated, dispute-capable design that was never built. Phase 2B implemented the
transaction completion event. Phase 3 added listing images/attachments (§2), notifications
(§8), the `GET .../listings/:id/transaction` lookup and enriched `TransactionSerializer` (§6),
and the frontend (§10). Phase 4 (this revision) added the My Listings view (§6, §10) and the
create/edit form's image/attachment upload UI (§10), documents the pre-existing
`marketplace-transaction-after-actions` `PluginOutlet` (§7) that earlier revisions never
described, and records the frontend QUnit coverage added alongside all of the above (§9); §6,
§7, §9, and §10 were updated accordingly. This document is authoritative; where it and the
code ever disagree, treat that as a bug in the document and fix the document, not the code,
unless a real behavior change is intended.

Remaining items are intentional V1 scope cuts, not gaps: see §10 (URL-addressable
search/filter state, a main-nav/sidebar link to `/marketplace`) and §1 (no plugin
stylesheet).

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
lib/marketplace/notifier.rb                transaction-lifecycle-event -> Notification (§8)
assets/javascripts/discourse/**            browse/create/edit/detail frontend (see §10)
assets/stylesheets/common/marketplace.scss not yet implemented (unstyled beyond core .btn/etc.)
spec/**
docs/MARKETPLACE_ARCHITECTURE.md           this file
docs/TRADE_REPUTATION_CONTRACT.md          public Trade Reputation integration reference
```

Namespacing: every Ruby class under `Marketplace::`, every table prefixed `marketplace_`,
every route under `/marketplace`, every setting prefixed `marketplace_`. Zero core monkey
patches; only `Guardian.prepend` inside a `reloadable_patch`.

Every file under `lib/marketplace/` is Zeitwerk-autoloaded: `Marketplace::Engine` registers
`config.autoload_paths << File.join(config.root, "lib")`. A new `lib/marketplace/*.rb` file
only needs to follow standard Zeitwerk path/constant naming — do not add a matching
`require_relative` in `plugin.rb` for it.

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

**Images/attachments (Phase 3).** No separate upload table or `image_ids` column. Images use
the same mechanism as every other Discourse model that accepts user-suppliable uploads
(`Draft`, `Badge`, `UserProfile`, etc.): they are embedded in `raw` using the composer's
normal `upload://<short-url>` markdown syntax, rendered into `cooked` by `PrettyText.cook`
(already done by `Listings::Create`/`Listings::Update`), and an `after_save` hook on
`Marketplace::Listing` calls `UploadReference.ensure_exist!(upload_ids:
Upload.extract_upload_ids(raw), target: self)` whenever `raw` changes. This both protects
referenced uploads from the core cleanup job and drops the reference to any upload no longer
mentioned after an edit (an `ensure_exist!` full sync, not additive-only). No new serializer
field is needed: `cooked` is already always exposed on `ListingDetailSerializer`, so any
embedded images render wherever a client renders `cooked` as trusted HTML.

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
- **No private data:** `TransactionSerializer` exposes transaction ids/timestamps plus
  `listing_title` and nested `BasicUserSerializer` buyer/seller public profile fields only —
  no emails, IPs, or trust-level internals.
- Site setting `marketplace_enabled` defaults **false**.

## 6. API / serializer boundary

Engine mounted at `/marketplace`, all responses `.json`. Routes actually defined
(`config/routes.rb`):

```
GET    /marketplace/categories

GET    /marketplace/listings            filters per ListingQuery (see lib/marketplace/listing_query.rb)
POST   /marketplace/listings
GET    /marketplace/listings/mine       current user's own listings, every status (login required)
GET    /marketplace/listings/:id
PUT    /marketplace/listings/:id
PUT    /marketplace/listings/:id/status
GET    /marketplace/listings/:id/transaction

POST   /marketplace/transactions        { listing_id }
GET    /marketplace/transactions/:id
POST   /marketplace/transactions/:id/confirm
POST   /marketplace/transactions/:id/cancel
```

There is no `POST .../reject`, `POST .../dispute`, or general `GET /marketplace/transactions`
index/list route -- a full "my transactions" listing endpoint is still a plausible future
addition (would need the indexes noted in §11 first) but is not built. `GET
/marketplace/listings/:id/transaction` (Phase 3) is narrower and does not need those indexes:
it returns only the current user's own **open, non-cancelled** transaction on that one
listing, scoped entirely by `listing_id` plus a `buyer_id = :uid OR seller_id = :uid` WHERE
clause. The existing partial unique index on `(listing_id) WHERE status <> 20` serves the
open-transaction lookup directly. A cancelled transaction is intentionally treated as no
current transaction and returns 404, allowing the listing (which cancellation reactivates)
to start a new purchase cleanly. No row outside the caller's own participation can ever be
returned, so no separate Guardian call is needed.

`GET /marketplace/listings/mine` (Phase 4, login required) returns the current user's own
listings across every status (`draft`/`active`/`reserved`/`sold`/`archived`), scoped entirely
by `WHERE seller_id = current_user.id` in `ListingsController#mine` -- the only way an owner
can rediscover a `draft` or `archived` listing of theirs, since the public `#index`
(`ListingQuery`) is mandatory-scoped to `active` listings in `enabled` categories only. No
separate Guardian predicate was needed, for the same reason `#transaction` above needs none:
no row outside the caller's own listings can ever be returned. Paginated the same shape as
`#index` (`page`/`per_page`/`has_more`; `per_page` clamped to `ListingQuery::MAX_PER_PAGE`),
serialized with the existing `ListingBrowseSerializer`.

`TransactionSerializer` (`app/serializers/marketplace/transaction_serializer.rb`) emits:
`id, listing_id, listing_title, buyer_id, seller_id, status, buyer_confirmed_at,
seller_confirmed_at, completed_at, cancelled_at, cancelled_by_id, created_at, updated_at,
buyer, seller` (Phase 3 added `listing_title` and nested `buyer`/`seller`
`BasicUserSerializer` objects -- public profile fields only, and only ever reachable by a
participant or staff via the existing `can_see_marketplace_transaction?` gate, so this is not
a new privacy surface). It does not emit `viewer_role` or `can_confirm`/`can_cancel`
booleans -- those remain a plausible future addition, not present today.

## 7. Trade Reputation contract (the small public surface)

**`Marketplace::TradeContract`** (`lib/marketplace/trade_contract.rb`), `VERSION = 1`,
exposes exactly one public lookup and one immutable value type:

```ruby
TransactionInfo = Data.define(:transaction_id, :listing_id, :buyer_id, :seller_id, :completed_at)

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

`TransactionInfo` exposes `listing_id` as the stable listing reference needed by Trade
Reputation feedback detail, and intentionally omits `status` (the method name already encodes
"completed"; a redundant status field would just invite a second, unnecessary check). It
never carries confirmation timestamps, cancellation metadata, a `User`, a `Listing`, or the
`Marketplace::Transaction` AR object itself — only five scalar/time fields, freshly queried
and copied on every call, so a caller mutating a `Transaction` they hold elsewhere in memory
cannot affect a previously returned `TransactionInfo`, and a caller holding a
`TransactionInfo` has no way to write back to Marketplace state (it is a `Data` object: no
setters, no `save`/`update`).

**Hard boundary**, unchanged from Phase 1 and still the load-bearing rule for everything
above: Trade Reputation may call `TradeContract` methods and reference `transaction_id`, and
nothing else. It may not query `marketplace_transactions`/`marketplace_listings`, `belongs_
to` a Marketplace model, share Marketplace's service context, or otherwise import
`Marketplace::Transaction`/`Marketplace::Listing`. Marketplace, symmetrically, never reads,
writes, or references any table owned by Trade Reputation. Full contract text lives in
`docs/TRADE_REPUTATION_CONTRACT.md`.

**UI integration point (`PluginOutlet`, pre-existing, documented here for the first time in
Phase 4).** Independent of the `TradeContract` API above,
`components/marketplace-listing-detail.gjs` renders a named, args-only extension point on the
transaction detail view:

```gjs
<PluginOutlet
  @name="marketplace-transaction-after-actions"
  @outletArgs={{lazyHash listing=this.listing transaction=this.transaction}}
  @defaultGlimmer={{true}}
/>
```

Marketplace is the outlet **provider** only: it renders the named outlet with `listing`/
`transaction` as outlet args and has no import, reference, or `defined?(...)` check for Trade
Reputation (or any other consumer) on this side. Trade Reputation is the **connector
consumer**: it supplies its own
`assets/javascripts/discourse/connectors/marketplace-transaction-after-actions/<name>.gjs` in
its own repo (the standard core `PluginOutlet` connector convention) to render UI -- e.g. a
"leave feedback" action -- using the outlet args, without Marketplace ever needing to know
Trade Reputation exists. This preserves the same hard boundary as the `TradeContract` API
above: Marketplace defines the seam and depends on nothing beyond it; any consumer depends on
Marketplace, never the reverse.

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

## 8. Notifications (Phase 3, implemented)

`lib/marketplace/notifier.rb` (`Marketplace::Notifier`) listens for Marketplace's own
transaction lifecycle `DiscourseEvent`s and creates one in-forum `Notification` per affected
participant:

- `:marketplace_transaction_created` (new, fired from `Transactions::Create` on a genuine new
  transaction, never a replay) -> notifies the seller.
- `:marketplace_transaction_first_confirmed` (new, fired from `Transactions::Confirm#record_
  first_confirmation`, never on the final/second confirmation or a same-side replay) ->
  notifies whichever participant has *not* yet confirmed, derived purely from the freshly
  reloaded `buyer_confirmed_at`/`seller_confirmed_at` (no extra payload needed).
- `:marketplace_transaction_completed` (existing event, unchanged trigger site -- Phase 3
  only adds a *listener*) -> notifies both participants.
- `:marketplace_transaction_cancelled` (new, fired from `Transactions::Cancel`, never on a
  cancelled replay or a rejected cancel-of-completed) -> notifies the participant who did
  *not* cancel, or both if staff cancelled.

All four triggers follow the exact `DB.after_commit { DiscourseEvent.trigger(..., transaction_
id, continue_on_error: true) }` pattern the completion event already established (§7): fired
only after a real commit, payload is always the scalar `transaction_id`, and a raising
listener is logged and swallowed rather than turning an already-successful request into a
failure. Listeners are registered in `plugin.rb` via `Plugin::Instance#on` (not raw
`DiscourseEvent.on`), which auto-guards on `enabled?` for free.

**Mechanism**: `Notification.create!(notification_type: Notification.types[:custom],
user_id: recipient_id, data: { message:, display_username:, topic_title:, title: }.to_json)`
with `topic_id`/`post_number` left `nil` -- verified from core (`db/structure.sql`: both
columns are nullable) and from the identical pattern already shipped in core's own bundled
`discourse-solved` plugin. There is no supported way for an out-of-tree plugin to add a new
named entry to `Notification.types` (that enum is fixed in `app/models/notification.rb`); the
`:custom` type plus a `data.message`/`data.title` i18n-key payload is the correct, supported
extension point for a plugin with no topic/post of its own. Client-side rendering (core's
`frontend/discourse/app/lib/notification-types/custom.js` and `base.js`) needs no
Marketplace-specific JS: without a `topic_id` the notification renders with no link (`linkHref`
returns `undefined`, a normal/handled case -- e.g. `admin_problems`/`new_features` notification
types behave the same way), which is an accepted Phase 3 limitation, not a bug, given there
was no listing/transaction frontend to link to before this same phase added one (see §10).
Locale keys live in `config/locales/client.en.yml` under `js.marketplace.notifications.*` and
`js.notifications.alt.marketplace.*`.

Delivery has the same best-effort posture as §7's completion event: no retry, no outbox, and
never the basis of correctness (transaction/listing state itself is, per §7's `TradeContract`
discussion).

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
  `transaction_id`/`listing_id`/`buyer_id`/`seller_id`/`completed_at`; `status` is not
  exposed; no AR object or AR-like mutability (`save`/`save!`/`update`/`update!` absent, no
  field setters); a `TransactionInfo` already returned is unaffected by later in-memory
  mutation of the underlying `Transaction`; exactly one public singleton method exists;
  `VERSION == 1`.
- **Query** (`spec/lib/marketplace/listing_query_spec.rb`): filter/sort correctness.
- **Notifier** (`spec/lib/marketplace/notifier_spec.rb`, Phase 3): each of the four notify_*
  methods against a fixture transaction -- correct recipient(s), correct `data` payload,
  and the "notify nobody" edge cases (unknown id, both sides already confirmed).
- **Service event specs** (Phase 3 additions to `create_spec.rb`/`cancel_spec.rb`, mirroring
  `confirm_spec.rb`'s existing "completion event" style): `:marketplace_transaction_created`
  and `:marketplace_transaction_cancelled` fire exactly once with the scalar transaction id
  on a real transition, zero times on a replay or rejected transition;
  `confirm_spec.rb` gained a matching "first confirmation event" group for `:marketplace_
  transaction_first_confirmed`.
- **Listing images** (Phase 3 addition to `spec/models/marketplace/listing_spec.rb`):
  `UploadReference` rows are created for uploads mentioned in `raw`, untouched when `raw`
  doesn't change, and synced (old dropped, new added) on an edit.
- **`GET .../listings/:id/transaction`** (Phase 3 addition to
  `spec/requests/marketplace/listings_controller_spec.rb`): returns the caller's own open
  transaction for buyer and seller alike; returns 404 for no transaction, a cancelled
  transaction, a missing listing, or anonymous access; and never returns another user's
  transaction on the same listing (non-enumerable).
- **`GET .../listings/mine`** (Phase 4 addition to
  `spec/requests/marketplace/listings_controller_spec.rb`): anonymous rejected (403); returns
  the owner's listings across every status; never returns another seller's listings
  (non-enumerable/IDOR); pagination (`page`/`per_page`/`has_more`); `per_page` clamped to the
  max; invalid `page`/`per_page` -> 400.

**Frontend (JS/QUnit), added Phase 4.** `test/javascripts/integration/components/`:
`marketplace-category-admin-test.gjs` (admin category CRUD), `marketplace-my-listings-test.gjs`
(renders the current user's listings across every status, the empty state, and load-more
visibility), and `marketplace-listing-form-test.gjs` (the upload control renders in create and
edit mode; an existing `raw` description is preserved on edit; a plain text-only description
still works with no uploads; and, using the same `pretender` + `upload-mixin:<id>:add-files`
app-event pattern core's own `avatar-uploader-test.gjs`/`watched-word-uploader-test.gjs` use to
drive a real mocked upload round-trip, a successful upload appends the server-returned
`upload://` markdown into the description). None of these were executed in this document's
own sandboxed authoring environment (no Discourse/Ember runtime available there); each was
confirmed green via the repository's `Discourse Plugin` CI workflow at the exact head that
introduced it.

## 10. Frontend (Phase 3, implemented; Phase 4 added My Listings and the upload UI)

`assets/javascripts/discourse/` -- verified against current core conventions (core's own
frontend source moved to a top-level `frontend/discourse/` directory; *plugin* assets still
live under `assets/javascripts/discourse/`, confirmed against core-bundled plugins like
`discourse-subscriptions`/`discourse-topic-voting` on the same ref). No admin UI; this is all
user-facing.

```
marketplace-route-map.js                      auto-discovered by filename convention
routes/marketplace/{index,new,listing,mine}.js
routes/marketplace/listing/edit.js
templates/marketplace/{index,new,listing,mine}.gjs  route-template .gjs files (receive @controller)
templates/marketplace/listing/edit.gjs
components/marketplace-browse.gjs              search/filter/sort + pagination + listing cards; links to "My Listings" (Phase 4)
components/marketplace-my-listings.gjs         Phase 4: current user's own listings, every status, paginated
components/marketplace-listing-form.gjs        shared create/edit form; Phase 4: image/attachment upload UI
components/marketplace-listing-detail.gjs      listing detail + transaction actions/state; PluginOutlet (§7)
```

Routes: `/marketplace` (browse+search/filter, `ListingQuery`'s `category_id`/`q`/`sort`
params via component-local `@tracked` state, not URL query params -- a deliberate Phase 3
scope cut), `/marketplace/new` (create), `/marketplace/listings/:listing_id` (detail;
`model()` also probes `GET .../transaction`, §6, to render transaction state for a returning
participant -- a 404 there is the common/expected case, handled locally, not surfaced),
`/marketplace/listings/:listing_id/edit`, and `/marketplace/mine` (Phase 4: the current
user's own listings across every status, via `GET .../listings/mine`, §6; redirects to
`/marketplace` if not logged in; linked from a "My Listings" button in the browse header,
shown only when logged in). All calls go through the existing JSON API (§6) via `ajax()`; no
backend surface beyond what's documented in §6. `cooked` is rendered as trusted HTML
(`htmlSafe`), matching how Discourse renders `cooked` content everywhere else -- safe because
`PrettyText.cook` already sanitized it server-side.

**Image/attachment upload UI (Phase 4, implemented).** `marketplace-listing-form.gjs` renders
an "Add image or file" control (hidden file input + `DButton`, driven by core's `UppyUpload`,
verified against current core source rather than guessed) below the description field in both
create and edit mode. A successful upload appends core's own `getUploadMarkdown()` result --
the same `upload://...` markdown the composer inserts -- to the existing `raw` value; §2's
`UploadReference` housekeeping is unchanged and still does all of the actual persistence-side
work, so a user can still embed `upload://...` markdown by hand exactly as before. The
description field itself moved from a bare `<textarea>{{this.raw}}</textarea>` to Ember's
`<Textarea @value={{this.raw}} />`, needed so markdown appended by the upload flow (not a user
keystroke) actually shows up in the field. No drag-and-drop or paste: the minimal
officially-supported pattern this follows (`UppyUpload` + a plain file input, the same shape
as core's own `form-template-field/upload.gjs`) doesn't wire those up either.

Still not built: URL-addressable search/filter state, and a main-nav/sidebar link to
`/marketplace` itself (the route is directly reachable -- via `/marketplace/new`'s and
`/marketplace/mine`'s own links back to it, and by URL -- just not surfaced from top-level
navigation chrome). Each remains a deliberate scope cut, not a correctness gap.

## 11. Risks and compatibility

- **Missing supporting indexes (new, Phase 2A).** `marketplace_transactions` has only the
  one partial unique index (§2) — no index on `buyer_id`, `seller_id`, or `completed_at`.
  A future "my transactions" endpoint (§6) or a Trade Reputation scan over completed
  transactions (should one ever be added — `TradeContract` itself is point-lookup-only and
  doesn't need this) will need a migration adding at least `(buyer_id, status)` and
  `(seller_id, status)` before shipping, per CLAUDE.md's N+1/indexing guidance. Still
  flagged; Phase 3's one-listing open-transaction lookup is served by the existing partial
  `listing_id` index and does not justify a general participant-history index yet.
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

Confirmed during Phase 1/2A/2B/3/4 review, against the installed core:

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
5. `UploadReference.ensure_exist!` (`app/models/upload_reference.rb`) — confirmed against
   core's own usage (`Draft`, `Badge`, `UserProfile`, `Category`, etc.): polymorphic
   `target`/`target_type`+`target_id`, does a full sync (deletes references not in the given
   `upload_ids`, then inserts the new set), used from every core model's `after_save`. §2.
6. Notification creation for a plugin with no topic/post of its own — confirmed against core's
   own bundled `discourse-solved` plugin (`Notification.create!(notification_type:
   Notification.types[:custom], user_id:, data: { message:, display_username:, topic_title:,
   title: }.to_json)`) and against `db/structure.sql` (`topic_id`/`post_number` nullable).
   `Notification.types` (`app/models/notification.rb`) is a fixed core enum with no plugin
   registration API — `:custom` plus a `data.message`/`data.title` payload is the correct
   extension point, not a gap to work around. Client rendering confirmed against core's
   `frontend/discourse/app/lib/notification-types/{base,custom}.js`. §8.
7. Plugin frontend conventions — confirmed against core-bundled plugins on the same ref
   (`discourse-subscriptions`, `discourse-topic-voting`, `chat`): `assets/javascripts/
   discourse/<name>-route-map.js` auto-discovered by filename; `routes/<path>.js` (plain
   `Route` with `model()`); `templates/<path>.gjs` (a route-template `.gjs` file receiving
   `@controller`, no explicit `Controller` class needed); interactive `.gjs` components
   (`@glimmer/component` + `@glimmer/tracking` + `{{on}}`/`{{i18n}}`/`<LinkTo>`); `ajax()`
   (`discourse/lib/ajax`) rejects on non-2xx with no automatic global error UI (that is the
   separate, opt-in `popupAjaxError` helper) — safe to `try/catch` an expected 404 silently.
   §10. Note: core's *own* frontend source moved to a top-level `frontend/discourse/`
   directory on this ref; plugin assets are unaffected and still live under
   `assets/javascripts/discourse/`.
8. Non-composer upload UI (Phase 4) — confirmed against a fresh shallow clone of
   `discourse/discourse@main`: `UppyUpload` (`discourse/lib/uppy/uppy-upload`) and
   `getUploadMarkdown()` (`discourse/lib/uploads`) are the supported minimal building blocks
   for an upload control outside the full composer, the same shape core's own
   `form-template-field/upload.gjs` and the bundled `discourse-ai` plugin's
   `rag-uploader.gjs` use; Ember's `<Textarea @value=...>` (`@ember/component`) is required
   (over a bare `<textarea>{{value}}</textarea>`) for a value mutated from outside a user
   keystroke to actually render, confirmed against core's own
   `form-template-field/textarea.gjs`. §7's `PluginOutlet` usage predates Phase 4 and needed
   no new verification. §10.
