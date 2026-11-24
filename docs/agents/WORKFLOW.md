# Engineering workflow

## Setup
Create manual, private agents using PROMPTS.md. Attach a shared skill using AGENTS.md if supported; otherwise paste its instructions into each agent. Connect only necessary tools. GitHub access does not guarantee write access or Studio execution. Role boundaries are behavioral, not path-level access controls. Use actual branch protection and least privilege where available. No automatic schedules initially.

## Coordination
Director approves scope and integration. Architect creates task specs and maintains contracts/decision records. Specialists implement on focused branches; QA independently reviews; director approves merge. Agents do not automatically communicate: use GitHub issues, PRs and explicit handoffs. Avoid concurrent edits to the same files. Architect resolves contract conflicts first.

Task template: objective; owner; dependencies; allowed scope; interfaces; acceptance criteria; tests; branch/PR; blockers.
Handoff template: task/PR link; base commit; changed files; contract changes; tests executed and results; unverified behavior; risks; next owner.

## First assignment to Architect
Inspect current Roblox main, FORGE dependency, live README, docs/ARCHITECTURE.md and original locked baseline. Establish shared contracts, decisions, roadmap and acceptance suite; do not pretend current prototype already meets target. Decompose remaining Block lifecycle into Construction, Geometry, Interaction, Infrastructure, Simulation and QA tasks. Validate FORGE boot, preview, server validation and commitment, compiled block, selection/move/rotate/resize/delete, undo/redo, save/reload, minimal machine states and rejection tests. Identify dependencies and safe integration order. Produce actionable plan for director approval before advanced features.

## Activation
Start Architect and QA, then Construction, Geometry, Interaction and Infrastructure as needed. Simulation for minimal state test; Mechanics after foundation; Harmonics research only. Keep expensive runs manual. Suggested reasoning where available: high for most; extra high for Geometry, Mechanics, Simulation, Harmonics.

## Status at setup
Repository README reports first Block prototype on main with fixed-axis Blocks, uniform resize, snapshots, a 32-block cap and DataStore-dependent saves. Rotation, full machine states, optimized deltas, modifier geometry, SmartFit and advanced mechanics remain incomplete. This is repository documentation, not independently executed Studio verification.
