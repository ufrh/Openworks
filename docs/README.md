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

These documents are migration planning and source evidence only. The game still uses the original six-tool implementation until Phase 1 and subsequent phases are implemented and tested.
