---
name: marketplace-implement
description: Implement one narrowly scoped Marketplace task with minimal context.
argument-hint: "[single implementation task]"
disable-model-invocation: true
context: fork
agent: general-purpose
model: sonnet
effort: medium
background: false
---

Implement exactly this task:

$ARGUMENTS

Before editing:
1. Check git status.
2. Read `CLAUDE.md`.
3. Read only the relevant sections of `docs/PROJECT_BRIEF.md` and, if needed, `docs/MARKETPLACE_ARCHITECTURE.md`.
4. Locate only files directly related to this task.

Rules:
- Make the smallest maintainable change.
- Do not scan or refactor unrelated code.
- Follow existing Discourse conventions and supported plugin APIs.
- Enforce authorization and ownership server-side.
- Add DB constraints/indexes when integrity or query patterns require them.
- Avoid N+1 queries.
- Preserve unrelated uncommitted changes.
- Do not commit, push, merge, deploy, or use destructive git commands.

Testing:
- Add/update only relevant tests.
- Run the smallest relevant test set.
- Inspect the final git diff.

Final response only:
1. Files changed
2. What changed
3. Tests
4. Remaining issue, if any

Maximum 8 lines.
