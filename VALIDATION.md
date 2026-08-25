# Validation

## Automated checks completed in this build

- `python -m py_compile server/server.py` — PASS.
- `python server/tests/smoke_test.py` — PASS:
  - players can create named battles;
  - player-created battles expose **Arena only**;
  - each battle keeps its own player limit and kills-to-win value;
  - clients can list and join battles by `battle_id`;
  - two simultaneous Arena battle instances have isolated snapshots/players.
- Additional room-logic check — PASS:
  - two rooms with kill limits `3` and `7` progress independently;
  - reaching 3 kills ends only the first room and does not stop the second room.
- `python tools/convert_arena_v3.py` — PASS in the supplied base build:
  - visual output: 60 glTF primitives/material groups;
  - 473,412 expanded visual vertices;
  - collision output: 2,993 triangles.
- Arena glTF/OBJ outputs and source textures/skybox files remain present.

## UI / content scope of this update

- Login, battle lobby/list and garage were rebuilt with visual assets from the supplied old client.
- The tank catalog, tank models, combat and equipment remain from the newer Godot project.
- No old playable maps were imported.
- Creating a battle always creates a new instance of **Arena**; other maps are unavailable in the create-battle window.

## Runtime limitation of this build environment

There is no Godot executable installed in the build container, so the final Godot 4.7 import/render could not be executed here. Client scripts/resources were statically checked, while the first local Godot import remains the authoritative visual/runtime check.
