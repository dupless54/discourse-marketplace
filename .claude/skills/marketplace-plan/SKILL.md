---
name: marketplace-plan
description: Plan one Marketplace architecture change without implementing it.
argument-hint: "[feature or architecture question]"
disable-model-invocation: true
context: fork
agent: Plan
model: opus
effort: high
background: false
---

Plan this Marketplace task:

$ARGUMENTS

Read `docs/PROJECT_BRIEF.md` and only the repository files needed for this task.
If `docs/MARKETPLACE_ARCHITECTURE.md` exists, read only the relevant sections.

Do not edit files.

Return a concise implementation plan covering only what matters:
- affected files/components
- data model/migrations/indexes
- services and state transitions
- authorization/security
- API/serializer boundary
- frontend impact if any
- tests
- migration/backward-compatibility risks

Preserve the boundary: Listing -> Transaction -> Trade Feedback.
Prefer the smallest maintainable design.
