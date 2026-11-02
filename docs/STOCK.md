# OPENWORKS M1 — Raw Stock & Physical Workpieces

This milestone introduces independent physical workpieces without changing FORM's canonical local-mm geometry. `Stock.create` constructs validated Block, Sheet, Rod, or hollow Tube meshes, stores material identity (Steel or Aluminum), dimensions, volume, calculated mass in kg, and an independent world transform.

## In Studio

Run Play with the `dev` Rojo branch. The new center-top **RAW STOCK** palette appears alongside the machining workbench and starts with one example of each shape on a physical work surface.

- Pick a shape and metal, set its dimensions in **millimeters**, then select **SPAWN STOCK**.
- Click and **hold the left mouse button on a workpiece** to pull it through the physics engine. This uses temporary AlignPosition and AlignOrientation constraints attached at the clicked point. Moving the mouse guides the workpiece; the mouse wheel changes grab distance.
- Release the mouse to remove the constraints. Workpieces are **unanchored with collisions by default**, so they fall, collide, and settle on the work surface.
- **TEMPORARILY SECURE / RELEASE** anchors or releases a piece for early workholding experiments. This is an interim vise substitute, not the eventual player-made fastener or welding system.
- Duplicate, delete, and cycle through pieces. Independent world placement is synchronized from each simulated MeshPart back into the workpiece record while Play is running.

Supported stock:
- Block: X, Y, Z.
- Sheet: X, thickness Y (up to 12 mm), Z.
- Rod: outer diameter and axial length (cylinder lies along local Y).
- Tube: outer diameter, length, and inner bore diameter.

Mass is computed from FORM mesh volume and steel/aluminum density. Roblox CustomPhysicalProperties approximates the same density; Roblox's world scale and collision solver are **not a certified physical mass model**. Tube collision uses MeshPart Hull fidelity and thus approximates a solid cylinder for contact—it does **not** currently provide a collision-accurate bore. This needs a compound collision proxy before passing an axle through a tube.

## Architecture and known limits

- `src/shared/Stock.lua`: canonical validated geometry, material, density, and independent transforms.
- `src/client/StockUI.lua`: local stock palette, selection, spawn/delete/duplicate, physical work surface, and temporary secure/release.
- `src/client/StockGrab.lua`: temporary mouse-controlled physics grip; constraints are destroyed on release.
- `src/server/StockTests.server.lua`: mesh topology, volume, mass, transform and invalid-stock regression tests.

**Important:** M1 is currently a **single-client prototype**. Objects are instantiated locally from EditableMesh and simulated on that client; they do not replicate as server-authoritative shared stock in multiplayer. The multiplayer workpiece registry, server validation, shared collision proxies, persistence, and mechanical assembly authority are later work. FORM remains independent of physics and of Roblox Instances.

The implementation has been pushed to `dev`, but this phase's new physics interactions still need to be tested in Roblox Studio. Passing previous FORM tests does not prove the new drag behavior.
