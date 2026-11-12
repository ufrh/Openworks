# Organized Primitive Catalog — Roblox Studio Smoke Test

This checklist requires a Studio session; source checks do **not** compile Luau or test real UI interactions.

1. Equip the unified **Build** tool. Press **B**. The header reads **BUILD LIBRARY**, and you see a search field, **My Components**, and grouped stock families.
2. Expand/collapse **Basic Shapes**, **Plates & Profiles**, **Shafts & Rods**, **Tubes**, **Holes & Slots**, **Gears**, **Pulleys**, **Fasteners**, and **Actuators**. **Other** holds older unrecognized templates; no entries disappear permanently.
3. Search by a display name (e.g. `spur gear`), by an exact internal ID (e.g. `Gear_20T`), and by a category (e.g. `tubes`). Confirm the matching items show immediately, including matches inside collapsed categories. Clearing search restores expanded/collapsed state.
4. Confirm `Gear_20T` appears as **Spur Gear · 20 teeth**, `Bevel90_12T` as **90° Bevel Gear · 12 teeth**, `Pulley_8U` as **Belt Pulley · Ø8 U**, `Bolt_100U` as **Hex Bolt · Ø1 × 8 U**, `HandCrank` as **Hand Crank**, and `Shaft` as **Round Shaft**, if those templates are present.
5. Where multiple tube, hole or slot variants exist, verify their size/shape suffixes stay distinguishable.
6. Select a displayed primitive, place it, press **Enter** to return to selection, select it, move and scale it. Ensure the Build HUD shows the friendly label.
7. Confirm **My Components** still lists saved blueprints and its items remain searchable, selectable and removable. Typing in search must not trigger a DataStore read for each character.
8. Exit and rejoin. Confirm previous plot saves and bank blueprints load with unchanged **TemplateId** values; this change only alters UI metadata.

For future generated templates, set the optional `CatalogName` and `CatalogGroup` attributes on the Studio source Model to override the fallback display name or one of the supported category labels **without changing the Model.Name**.
