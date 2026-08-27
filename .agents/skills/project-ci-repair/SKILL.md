---
name: project-ci-repair
description: Diagnose a concrete failing CI job and produce the smallest justified repair without broadening scope.
---
# CI repair
Read root/local rules and current state. Inspect the failing job/log and identify the first actionable root cause. Classify code defect, test/fixture defect, or infrastructure/transient failure. Change only the smallest justified surface, run targeted validation, and preserve original scope. Update state only with verified facts. Do not turn a CI repair into architecture/product expansion.
