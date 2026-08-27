# Repository map

Use this to choose paths before searching. Source code remains authoritative if the map becomes stale.

- `plugin.rb` — plugin entrypoint/registration.
- `app/` — Marketplace models, services, controllers, serializers; read `app/AGENTS.md` when entering.
- `lib/` — Guardian/query/integration helpers including the TradeContract boundary; read `lib/AGENTS.md`.
- `db/` — migrations/schema changes; read `db/AGENTS.md`.
- `spec/` — plugin specs/fabricators; read `spec/AGENTS.md`.
- `config/` — routes/settings/configuration surfaces.
- `docs/` — stable contracts and AI state/workflow docs; do not preload wholesale.
- `.agents/skills/` — on-demand procedures; load only the matching skill.

Fast read order: root `AGENTS.md` -> task packet -> nearest local `AGENTS.md` -> exact symbol/source -> exact test. Open `DECISIONS.md`, `COMMANDS.md`, or `CURRENT_STATE.md` only when the task needs them.
