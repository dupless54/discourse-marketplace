# Durable decisions

Load only when an architecture or integration choice is relevant.

- Marketplace owns listing and transaction truth; reputation remains a separate consumer.
- `Marketplace::TradeContract` is the supported reputation integration seam; consumers must not couple to Marketplace models/tables/private services.
- Listing state and transaction state remain separate server-authoritative state machines.
- Participant authorization and transition validity are enforced server-side; client state is advisory only.
- Integrity that must survive retries/concurrency belongs in persistence constraints and idempotent transition logic where appropriate.

Do not record temporary PR/CI status here; use `CURRENT_STATE.md` for volatile facts.
