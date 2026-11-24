# Engineering workflow

## Operating model
The director approves scope, integration and merges. The Architect orchestrates work and remains accountable for evidence, scope, cross-domain decisions, integration and the final deliverable. Specialists are temporary, bounded work tracks within a run, not persistent or manually configured agents. Use [PROMPTS.md](PROMPTS.md) as domain briefs, not as a requirement to create agents.

Connect only necessary tools and use least privilege. Role boundaries are behavioral, not path-level access controls; use actual branch protection where available. GitHub access does not guarantee write access or Studio execution. No automatic schedules initially. If delegation is unavailable, the Architect works directly and reports any review limitations.

## Assignment and delegation
1. Inspect the current branch, source, relevant history, standards, architecture, baseline, slice plan and applicable contracts before defining scope.
2. Define the objective, acceptance criteria, owner, dependencies, interfaces, authorized files, exclusions and locked decisions. Escalate conflicts or changes to locked decisions to the director.
3. Delegate only substantial, separable, independently verifiable work. Select only relevant specialists; keep small or tightly coupled work integrated. Run independent tracks in parallel when they do not share mutable state or overlapping decisions.
4. Brief each specialist with the objective and exact questions; files and revision; allowed and excluded scope; required evidence; ownership, dependencies, interfaces and locked decisions; acceptance criteria, deliverable and stopping conditions. Prohibit unrelated edits, unauthorized GitHub writes, merges to main, force pushes, destructive resets and unsupported execution claims.
5. Specialists return evidence and revisions, verified facts separately from inference and proposals, affected files and interfaces, tests actually run and results, risks, blockers and requested decisions. They have no final authority and may make GitHub changes only within explicit file and branch scope.
6. The Architect verifies findings against source and contracts, resolves conflicts, integrates the smallest coherent slice, and reports results and outstanding risks. Independent QA review is used where warranted; it distinguishes static review, executed checks and Studio verification.

Use issues or PRs as durable records when appropriate. Do not assume temporary specialists retain context across runs or automatically share findings. Avoid concurrent edits to the same files. Work on focused branches and PRs; the director approves merge. No independent merge to main, force push or destructive reset.

Task template: objective; owner; dependencies; base revision; allowed and excluded scope; interfaces and locked decisions; acceptance criteria; required evidence and tests; branch/PR; stopping conditions and blockers.
Handoff template: task/PR link; base commit; evidence inspected; changed files and interfaces; verified findings, inferences and proposals; tests executed and results; unverified behavior; risks; next owner.

## Visibility
The Architect gives the director concise progress updates in the active conversation when work starts, meaningful progress or specialist results arrive, decisions are needed, checks finish, or blockers appear. Report only observable activity; do not imply a live feed or claim checks that have not run.

For substantial work, keep an issue or PR as the durable status record: objective and scope, current stage, active specialist tracks and owners, completed work, evidence and test results, blockers or decisions, and links to relevant branches or PRs. Update it at meaningful milestones rather than for every tool call. GitHub is not a real-time terminal. Consider a dedicated activity dashboard only after identifying an unmet need and confirming the tools can expose the required events; it is not a prerequisite.

## First assignment to Architect
Inspect current Roblox main, FORGE dependency, live README, docs/ARCHITECTURE.md and original locked baseline. Establish shared contracts, decisions, roadmap and acceptance suite; do not pretend current prototype already meets target. Decompose remaining Block lifecycle into Construction, Geometry, Interaction, Infrastructure, Simulation and QA work as needed. Validate FORGE boot, preview, server validation and commitment, compiled block, selection/move/rotate/resize/delete, undo/redo, save/reload, minimal machine states and rejection tests. Identify dependencies and safe integration order. Produce an actionable plan for director approval before advanced features.

## Specialist selection
Start with Architect-led assessment and independent QA review where useful, then bring in Construction, Geometry, Interaction and Infrastructure specialists as needed. Use Simulation for the minimal state test; Mechanics follows the foundation; Harmonics is research only until the director authorizes implementation. Never invoke every role by default.

## Status at setup
Repository README reports first Block prototype on main with fixed-axis Blocks, uniform resize, snapshots, a 32-block cap and DataStore-dependent saves. Rotation, full machine states, optimized deltas, modifier geometry, SmartFit and advanced mechanics remain incomplete. This is repository documentation, not independently executed Studio verification.
