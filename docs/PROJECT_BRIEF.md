# Marketplace V1 Product Brief

## Goal
Create a native Discourse marketplace where authenticated forum users can publish listings and complete a sale with another forum user.

V1 does not process money or act as an escrow/payment provider. It records the listing and the confirmed trade relationship. Payment integration may be added later.

## Listing V1
A listing should support:
- seller
- title
- description
- category
- price
- currency
- images/attachments using supported Discourse mechanisms
- status
- created/updated timestamps

Expected user actions:
- create
- edit own listing
- close/archive own listing
- browse
- search/filter
- view listing details

Recommended listing states:
- draft
- active
- reserved
- sold
- archived

Exact names may change if existing project conventions suggest something better.

## Transaction V1
A trade reputation record must never be based directly on a listing alone.
A valid transaction is the proof that buyer and seller actually traded.

Required relationship:
Listing -> Transaction -> Trade Feedback

A transaction references:
- listing
- seller
- buyer
- status
- seller confirmation timestamp
- buyer confirmation timestamp
- completion/cancellation/dispute timestamps where relevant

Recommended flow:
1. Listing is active.
2. Seller selects the forum user who bought the item/service and starts sale confirmation.
3. Seller confirmation is recorded.
4. Buyer receives a confirmation action.
5. Buyer confirms or rejects.
6. On valid confirmation, transaction becomes completed and listing becomes sold.
7. Only a completed transaction unlocks feedback for both participants.

Recommended transaction states:
- pending_confirmation
- completed
- cancelled
- disputed

State transitions must be explicit, authorized, idempotent, and protected against duplicate/concurrent requests.

## Trade Reputation Contract
Marketplace must expose the minimum stable integration surface needed for the separate reputation plugin to answer:

- Does transaction X exist?
- Is it completed?
- Who is the seller?
- Who is the buyer?
- Which listing does it belong to?
- When was it completed?
- May user A review user B for this transaction?

Do not make the reputation plugin depend on marketplace internals when a small service/event/API contract can be used.

After the transaction implementation stabilizes, create:
`docs/TRADE_REPUTATION_CONTRACT.md`

Keep that contract concise.

## Notifications
V1 should notify users for important transaction actions when supported cleanly:
- seller selected buyer / confirmation requested
- buyer confirmed
- buyer rejected or transaction entered dispute/cancel path
- transaction completed

## Performance
Design for tens of thousands of listings and transactions:
- pagination
- useful indexes
- no loading entire histories into memory
- no N+1 queries

## Out of scope for V1
Unless explicitly requested later:
- forum-hosted payment processing
- escrow
- shipping integration
- paid listing boosts
- auctions
- complex dispute arbitration
- advanced analytics dashboards
