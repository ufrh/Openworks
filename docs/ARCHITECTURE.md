# Architecture

## Single-place source of truth

One Rojo project (`default.project.json`) maps exactly three source roots:

- `src/shared` -> `ReplicatedStorage.Openworks`
- `src/server` -> `ServerScriptService.Openworks`
- `src/client` -> `StarterPlayer.StarterPlayerScripts.Openworks`

Non-code Studio assets remain in the place file until an explicit asset synchronization strategy is chosen. Do not maintain a second hidden copy of script source inside Studio.

## Planned domains

- FORM: deterministic solid modeling and mesh topology.
- Manufacturing: operation validity, tools, workholding, material edits.
- Mechanics: assemblies and mixed-fidelity physics.
- Electrical: circuits, power, signals, RF abstractions.
- Automation: safe programmable components and UI.
- Persistence: parts, construction operations, workshop state.
- Economy: materials and manufacturing contracts.

Client-heavy geometry computation must not allow client-authoritative inventory or impossible material generation. Server validates canonical edits, manages shared physical machines and persistence. Detailed mesh reconstruction is client-side where feasible.

No large framework is required to bootstrap these domains.
