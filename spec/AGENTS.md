# Marketplace tests

- Prefer real models/services and decisive assertions.
- Fabricators must match the schema actually running in CI; do not use stale attributes or obsolete Fabrication syntax.
- Concurrency claims require a test that exercises the race meaningfully, not only sequential calls.
- Contract specs must pin public `TradeContract` behavior without exposing AR internals.
- Request specs should include authorization/non-enumeration and ignored client-owned fields where relevant.
- Never report runtime specs as passing if they did not execute.
