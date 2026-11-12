# OPENWORKS documentation

- **[Current architecture](ARCHITECTURE.md)** — source boundaries, ownership, simulation and persistence invariants.
- **[Current regression checklist](QA_REGRESSION.md)** — the authoritative Studio Play acceptance checklist for the `dev` branch.
- **[Archived implementation log](ARCHIVED_IMPLEMENTATION_LOG.md)** — historical append-only README, preserved without deleting earlier decisions.
- **[Rebuild notes](REBUILD_NOTES.md)** — original design-reset context.
- **`PHASE_*.md`** — historical smoke-test guides. These may refer to obsolete tools, Ctrl+G assembly registration, motor controls and superseded sizing mechanics. Treat them as archival, not current instructions.

Current controls live in the root [README](../README.md). Changes to engine behavior should update the root README and current architecture/test documents; do not append new phases to the README.

## UI v2 reorganization

- **[Phase 0 frozen baseline](UI_V2_PHASE_0_BASELINE.md)** — branch, baseline SHA, current six-tool system, source checks, legacy permissions, and unverified Studio gates.
- **[UI v2 regression matrix](UI_V2_REGRESSION_MATRIX.md)** — six saved-machine fixtures, 22 UI acceptance tests, authorization migration map, and evidence checklist.
- **[Phase 1 implementation and Studio smoke test](UI_V2_PHASE_1_IMPLEMENTATION.md)** — three-tool/eight-subtool routing, permissions, interim keybinds, CI status, and unverified runtime acceptance.
- **[Phase 2 visualization implementation and known CSG limits](UI_V2_PHASE_2_IMPLEMENTATION.md)** — shared 12-edge outlines, connection confirmation, assembly feedback, ghost geometry strokes and Studio test cases.
- **[Phase 3 unified Explorer, Properties, context menus and tooltips](UI_V2_PHASE_3_IMPLEMENTATION.md)** — implementation details, permission filters, inline editing, and Studio acceptance cases.
- **[Phase 4 unified mechanical connections](UI_V2_PHASE_4_IMPLEMENTATION.md)** — shared Connect picker, shaft/hole/gear mounting, validated server actions, retired shortcuts, and Studio regression.
- **[Phase 5 unified Assembly & Simulation](UI_V2_PHASE_5_IMPLEMENTATION.md)** — inline assembly drafts, exact membership, shared run/pause/reset/telemetry controls, actuator input focus and Studio acceptance.
- **[Phase 6 final cleanup and regression handoff](UI_V2_PHASE_6_IMPLEMENTATION.md)** — retired UI modules, no duplicate live HUDs, Build Fasteners correction, Luau parser CI, and mandatory Studio release gates.

These documents cover committed UI v2 client source work on the isolated feature branch. The original six-tool implementation remains on the untouched `dev` branch. **None of the new UI has been certified in Roblox Studio yet.**
