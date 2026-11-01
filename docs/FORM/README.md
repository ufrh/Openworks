# FORM

Geometry kernel for OPENWORKS.

Implementation: `src/shared/FORM/init.luau`. Studio smoke tests: `src/server/FORMTests.server.luau`.

Current scope: centered box generation, bounds, signed volume, and basic triangle edge incidence / winding validation.

Not implemented: full manifold validity, self-intersection detection, planar splitting, CSG, bevels, EditableMesh rendering. Tests have not yet run in Studio.
