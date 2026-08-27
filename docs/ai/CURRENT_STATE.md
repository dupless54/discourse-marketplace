# Current state

Main baseline at context setup:
`9dc57b2d3a494feb41eae3857195c209b6c16443`

Open integration work at setup:
- PR #6: `FEATURE: expose listing reference for trade detail`
- PR #6 adds the read-only listing reference required by Trade Reputation detail work and includes the Marketplace Fabrication 3 category-sequence compatibility repair uncovered by cross-plugin CI.
- Trade Reputation PR #10 depends on this Marketplace contract work.

Do not assume an open PR is merged or that its branch equals `main`. Re-read the exact PR/head before dependent work. Current source/tests and current GitHub state override this checkpoint.
