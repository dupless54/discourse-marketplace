# Discourse Marketplace — Project Instructions

This repository is a production Discourse plugin.

## Context discipline
- Read only files required for the current task.
- Search before opening many files.
- Do not scan unrelated directories or sibling repositories.
- Prefer targeted tests over the full suite.
- Keep final summaries under 8 lines unless asked otherwise.
- Do not load large docs unless the current task needs them.

## Implementation
- Follow the conventions already used by this repository and current Discourse plugin APIs.
- Prefer supported plugin APIs over monkey patches.
- Make the smallest maintainable change.
- Do not refactor unrelated working code.
- Reuse existing components/services when practical.
- Keep backend authorization server-side.
- Never trust client-provided ownership, seller, buyer, status, or permission fields.
- Avoid N+1 queries and add indexes for frequently queried columns.
- Preserve backward compatibility unless the task explicitly changes an API.

## Domain boundaries
Keep these concepts separate:

Listing -> Transaction -> Trade Feedback

Marketplace owns Listings and Transactions.
Trade Reputation is a separate plugin and must integrate through a small documented contract.

## Listing rules
- A listing has exactly one seller.
- The seller is derived from the authenticated user, never trusted from client input.
- A seller cannot buy their own listing.
- Listing state and transaction state are separate concepts.

## Transaction rules
- A transaction must reference one listing, one seller, and one buyer.
- Only transaction participants and authorized staff may act on it.
- Invalid state transitions must fail server-side.
- Completion must be idempotent and safe against duplicate/concurrent requests.
- Important transitions require timestamps.
- Completed/cancelled/disputed history must remain auditable.

## Security
- Protect against IDOR, mass assignment, replay, duplicate requests, race conditions, and self-transactions.
- Use database constraints/unique indexes for integrity where appropriate.
- Do not expose private data or secrets in API responses or logs.

## Tests
For changed behavior, test the smallest relevant scope:
- happy path
- authorization failure
- invalid input/state
- duplicate/replayed request when relevant
- concurrency-sensitive behavior when relevant

Before finishing, inspect the diff for accidental changes.

## Git / deployment
- Never commit, push, merge, rebase, reset, force-push, or deploy unless explicitly requested.
- Never overwrite unrelated uncommitted user changes.
- Never expose credentials, tokens, private keys, or production secrets.

## Documentation
- `docs/PROJECT_BRIEF.md` contains the V1 product requirements.
- `docs/MARKETPLACE_ARCHITECTURE.md` should contain the approved implementation architecture once created.
- `docs/TRADE_REPUTATION_CONTRACT.md` should contain only the public integration contract needed by the reputation plugin.
