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

Stop for unresolved architecture, schema/migration, authorization/security, public-contract, or product ambiguity. Preserve unrelated work and `.claude/settings.local.json`. Never force-push, reset/clean, delete branches, deploy, or make destructive DB changes.

## CI-only merge gate
Claude/Gemini/Codex reviewer or verifier approval is not required and must never block merge. Do not request or wait for AI approvals as a merge condition.

For a normal scoped PR, the merge gate is CI only:
- validate the exact changed paths still match the task;
- use only the latest exact PR head SHA;
- require the official `Discourse Plugin` CI workflow on that exact head to conclude GREEN;
- if the repository exposes any additional required Discourse-owned CI/check context, it must also be GREEN;
- a new commit invalidates all older CI evidence;
- `NO_CI`, missing, skipped, pending, cancelled, neutral, stale-head, or failed checks are not GREEN.

When the latest exact head is GREEN and no unresolved security/schema/product/architecture blocker remains, the agent is pre-authorized to merge without asking for another user confirmation. Prefer squash merge with `expected_head_sha` when supported. Never weaken tests or broaden scope just to obtain GREEN.

## Token discipline

Minimum unnecessary tokens, not minimum reasoning. Prefer exact symbols, paths, diffs, failing assertions, and targeted reads. Do not summarize whole files or reread stable docs without a concrete need.

## Adaptive model / effort routing

Classify execution risk with `docs/ai/EFFORT_ROUTER.md` before broad reads. Start at the lowest sufficient tier: T0 mechanical, T1 routine, T2 high-risk, T3 exceptional. Escalate for risk/ambiguity rather than task size, and de-escalate when the risky phase ends. Use platform-native workers under `.claude/agents/` or `.codex/agents/` when supported; never trade away correctness, security, or validation to save tokens.

## On-demand skills

Reusable procedures live under `.agents/skills/`. Read only the skill matching the task: `task-packet`, `project-plan`, `project-implement`, `project-review`, `project-final-verify`, `project-ci-repair`, `project-schema-review`, `project-security-review`, or `project-update-state`.

## Live Discourse developer source gate

Canonical live upstream index: https://meta.discourse.org/t/developer-guides-index/308036?tl=en

For any Discourse-version-sensitive implementation, refactor, review, or compatibility decision:
- start at the live Developer Guides Index and open only the task-relevant official topic(s);
- for plugin work prioritize **Code & Internals + Plugins**; for theme work prioritize **Code & Internals + Themes & Components / Theme Developer Tutorial**; use environment/general guides only when relevant;
- verify version-sensitive APIs and deprecations against current `discourse/discourse` core or the current official plugin/theme skeleton before coding when needed;
- current official docs/core beat remembered examples, old snippets, and copied local guidance unless the repo deliberately targets an older validated release via `.discourse-compatibility` / d-compat;
- do not preload the full index: read the nearest local rules and target source/tests first, then fetch only the upstream guide(s) needed for the current choice.
