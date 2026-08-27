# Marketplace schema and migrations

Schema changes are high risk. Read `.agents/skills/project-schema-review/SKILL.md` before changing migrations or indexes.

- Preserve transaction/listing integrity at DB level where practical.
- Consider existing rows, null/default/backfill behavior, uniqueness, FK actions, lock duration, index cost, and rollback/recovery.
- Never make destructive production changes as part of ordinary development.
- Do not add speculative indexes without a demonstrated query path.
