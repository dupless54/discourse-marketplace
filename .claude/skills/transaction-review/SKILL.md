---
name: transaction-review
description: Read-only security and integrity review of Marketplace transaction code.
argument-hint: "[transaction area to review]"
disable-model-invocation: true
context: fork
agent: Explore
model: opus
effort: high
background: false
---

Perform a read-only review of:

$ARGUMENTS

Inspect only transaction/listing/authentication files necessary for the review.
Do not edit files.

Check specifically for:
- IDOR / authorization bypass
- client-controlled seller/buyer/owner fields
- self-transactions
- invalid state transitions
- duplicate or replayed requests
- concurrent completion / race conditions
- missing transaction locking or atomicity where required
- missing DB constraints/unique indexes
- inconsistent listing and transaction state
- unsafe cancellation/dispute behavior
- mass assignment
- private data exposure
- N+1 queries on transaction/history endpoints

Report only concrete issues.
For each issue include: severity, file/location, failure scenario, minimal fix.
End with counts: CRITICAL / HIGH / MEDIUM / LOW.
Keep it concise.
