# Marketplace backend

Local rules for `app/`.

- Controllers stay thin; authorization and state transitions remain server-authoritative.
- Never trust client-supplied seller, buyer, owner, status, timestamps, or permission fields.
- Services own mutations and explicit transition rules.
- Preserve idempotency and concurrency safety for transaction lifecycle operations.
- Models enforce durable invariants with validations plus DB constraints where justified.
- Serializers expose only viewer-appropriate fields; avoid IDOR/private-state leakage.
- Do not introduce Trade Reputation model/table dependencies here.
