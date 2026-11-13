# OpenWorks — Edit tool 2, fitting, camera and plot recovery (2026-11-13)

Build is hotbar **1**, Edit is hotbar **2**, Mechanics is **3**, and Assembly & Simulation is **4**.

## Studio acceptance test (runtime required)

1. Press **1** to equip Build. Open the part library with **B**, select a shaft and a larger tube/drilled hole, and place each. Confirm Build's placement tools do not mutate existing parts.
2. Press **2** for Edit. Select a shaft (or component containing one), press **L**, aim at the tube's hole center, click, check the live preview, choose Rotate / Slide / Rotate + Slide / Fit Only, and verify it creates the chosen physical relationship. Verify Edit can issue *fine-fit*, *pose* and reset without `Use Mechanics` authorization failures.
3. Reverse the operation: select an opening-bearing body in Edit and press **L**. Aim at a fixed shaft, click and confirm. The opening-bearing body should move to the shaft while the shaft remains stationary. Also test multi-hole/multi-shaft components.
4. Put a gear or pulley onto a shaft. Choose Rigid. Its connection should be a rigid hub weld, never a loose hinge, and Edit should exit the incompatible fine-fit step.
5. In freecam, use **WASD** and **Space/Ctrl** to fly. Descend near the plot floor (minimum floor-relative camera Y is 0.085 studs); do not drift laterally after moving into a blocking wall/floor. Roll the mouse wheel to smoothly zoom via FOV. While fitting, wheel should adjust insertion instead; after fit it should zoom.
6. Press **F6** and save. Restart in Studio with API access enabled, load, and verify parts and joints restore. If a saved template is unavailable or now has invalid metadata, the loader preserves that record and its linked joints in cloud data instead of deleting it, loads compatible parts, reports the template reason in Studio Output, and retains preserved records on the next save.
7. Check tool change, ray-picked hole center, undo/redo, resizing/paint, component bank save and reload, gear/shaft fit, multiple connected openings, assembly simulation and reload.

### Known verification limit

Static contracts are not live Roblox physics or DataStore tests. The migration intentionally retains old saved records if they cannot be rendered; unavailable parts do not appear in Studio until their templates are repaired. Do **not** clear DataStores to mask a load error.
