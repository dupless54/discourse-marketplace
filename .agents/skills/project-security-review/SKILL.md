---
name: project-security-review
description: Review authorization, privacy, input trust, replay, external interfaces, and secret handling for a changed surface.
---
# Security review
Read root/local rules and inspect the exact diff. Check authentication/authorization, IDOR, mass assignment, client-owned state, privacy leakage, replay/idempotency, races, rate limits where relevant, secrets/logging, external callbacks/webhooks, and unsafe network access. Report concrete exploit paths or missing controls; do not invent theoretical blockers without evidence.
