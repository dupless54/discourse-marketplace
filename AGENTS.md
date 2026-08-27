# Discourse Marketplace Agent Router

Canonical instructions for ChatGPT/Codex, Claude, and Gemini.

## Authority and context

When information conflicts: current source/tests > `docs/ai/CURRENT_STATE.md` > nearest local `AGENTS.md` > stable architecture/docs > plans/history.

Read the minimum context required. Always read this file. Then read only the nearest local `AGENTS.md` files for areas actually inspected or changed. For multi-session work, read the active `docs/ai/work/<feature>/state.md` first and only the relevant plan section. Do not preload unrelated docs or completed phases.

Area router:
- backend/models/controllers/services -> `app/AGENTS.md`
- queries/contracts/Guardian helpers -> `lib/AGENTS.md`
- schema/migrations -> `db/AGENTS.md`
- specs/fabricators -> `spec/AGENTS.md`

## Fast task path

For non-trivial work, use `.agents/skills/task-packet/SKILL.md` before broad reads. Use `docs/ai/REPO_MAP.md` to locate code, `COMMANDS.md` only when validation is needed, and `DECISIONS.md` only when an architecture/integration choice is relevant. Skip the formal packet for trivial one-file edits.

## Project invariants

Marketplace owns listings, categories, transactions, and transaction truth. Trade Reputation is a separate consumer and must integrate only through a small documented public contract.

- A listing has exactly one seller, derived from the authenticated user.
- A seller cannot buy their own listing.
- Listing state and transaction state are distinct.
- A transaction references one listing, one seller, and one buyer.
- Only participants and authorized staff may act on a transaction.
- Invalid transitions fail server-side.
- Completion/cancellation paths must remain idempotent and safe against duplicate or concurrent requests.
- Important transitions keep auditable timestamps/history.
- Protect against IDOR, mass assignment, replay, duplicate requests, races, and self-transactions.
- Use DB constraints/indexes for integrity where appropriate.
- Do not expose private data or secrets.

`Marketplace::TradeContract` is the public reputation integration seam. Preserve its documented behavior and immutable value-object boundary. Do not silently expand or break it.

## Implementation and tests

Use current Discourse plugin APIs verified from source when behavior is version-sensitive. Prefer supported plugin APIs, smallest maintainable changes, server-side authorization, bounded queries, and existing seams. Avoid unrelated refactors and N+1 queries.

For changed behavior cover the smallest relevant set: happy path, authorization failure, invalid input/state, duplicate/replay, and concurrency-sensitive behavior when relevant. Never claim a test passed unless it actually ran; report unavailable checks as NOT RUN.

## Safety and delivery

Stop for unresolved architecture, schema/migration, authorization/security, public-contract, or product ambiguity. Preserve unrelated work and `.claude/settings.local.json`. Never force-push, reset/clean, delete branches, deploy, or make destructive DB changes. Commit/push/PR/merge only when the current user task explicitly authorizes that action.

## Token discipline

Minimum unnecessary tokens, not minimum reasoning. Prefer exact symbols, paths, diffs, failing assertions, and targeted reads. Do not summarize whole files or reread stable docs without a concrete need.

## On-demand skills

Reusable procedures live under `.agents/skills/`. Read only the skill matching the task: `task-packet`, `project-plan`, `project-implement`, `project-review`, `project-final-verify`, `project-ci-repair`, `project-schema-review`, `project-security-review`, or `project-update-state`.
