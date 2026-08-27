---
name: project-review
description: Independently review a task diff for concrete blocking defects without relying on builder reasoning.
---
# Independent review
Read the locked task, root/local rules, changed files/diff, and test/CI evidence. Inspect source yourself. Check scope, correctness, edge cases, auth/privacy, framework compatibility, DB/performance when relevant, and meaningful test gaps. Do not manufacture findings or reject for style alone. Return APPROVE, REJECT, or NEEDS_HUMAN with concise evidence and required fixes.
