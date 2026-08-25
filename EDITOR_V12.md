# v12 — editor-friendly Arena

- `main.gd` now instantiates `client/scenes/maps/arena_editable.tscn` for Arena v3.
- Arena lighting/environment/puddles/spawns are real scene nodes, not runtime-generated setup.
- `arena_visual_editor.gltf` removes the old `bims` beam primitive and removes `COLOR_0` baked-light modulation.
- `lights_editor.dae` removes the duplicated `Shadows` layer and `Direct01` top light, leaving local fixture lights for manual editing.
- `ChemicalPools` contains four editable pool nodes with water shader + individual OmniLight3D.
- `SpawnPoints/Spawn_0..2` are editor markers and are read by the game at spawn time.
- `Collision/PhysicsMesh` remains the original Arena physics mesh and creates its trimesh collision at runtime.
- `Props` and `Effects` are intentionally empty editor folders for user-authored additions.
- Russian workflow guide: `ARENA_EDITOR_GUIDE_RU.md`.

Validation: `python server/tests/smoke_test.py` => PASS.
Godot binary is not installed in the build environment, so first editor import remains to be validated on the user's machine.
