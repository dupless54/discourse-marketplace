---
name: project-schema-review
description: Review migrations, indexes, constraints, and stored-data changes for correctness and production safety.
---
# Schema review
Inspect DDL, affected queries/models, existing-data behavior, null/default/backfill policy, uniqueness/FKs/checks, index usefulness, lock/table-scan risk, rollback/recovery, and deploy ordering. Require evidence for large-table assumptions. Stop for irreversible or ambiguous production-data decisions. Do not execute destructive production operations.
