---
name: project-ci-repair
description: Diagnose a failing latest-head CI check and produce bounded, minimum-scope remediation.
---
# CI repair
Inspect the failing job and identify the first actionable root cause. Classify code, test/fixture, dependency, or infrastructure/transient failure. Produce only the smallest justified repair and run targeted validation. If an authorized Git/GitHub step creates a new head SHA, required CI must be evaluated again for that new SHA; older CI evidence is invalid. Never weaken tests or broaden architecture/product scope merely to obtain green CI. Maximum automatic repair rounds: 3. After 3 unresolved rounds, or when a material architecture/security/schema/product decision is required, return `NEEDS_HUMAN` with concise evidence.
