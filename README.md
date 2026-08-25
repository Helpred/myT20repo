# Tanki 20 — Godot multiplayer

This is the complete newer Godot multiplayer project with the requested old-client UI transplant for **login**, **battle lobby/list** and **garage**, plus user-created battles with an automatic Godot map catalog.

## What changed in this build

### Login and menus

- The login window now uses the supplied old client's window, input, button and title textures.
- The main lobby has an old-style battle browser instead of immediately entering one global room.
- The garage uses the old visual framing while keeping the **new project's tanks, equipment catalog and tank preview**.
- Other battle HUD/UI was intentionally left on the newer implementation for this stage.

### Player-created battles

Authenticated players can:

1. open the battle list;
2. create a named battle;
3. choose any map discovered in `client/scenes/maps/*.tscn`;
4. choose the maximum number of players;
5. choose the **number of kills required for victory**;
6. select that battle from the list and join it.

Maps are discovered automatically by both the Godot client and Python server. Adding `arena_day.tscn` to `client/scenes/maps/` is enough for it to appear in the create-battle map selector; no hard-coded map list needs to be edited. Optional same-name PNG/JPG/WEBP previews are also discovered automatically. Multiple battles have independent players, snapshots, round state, battle fund, supplies and kill limits.

## Tanks

The playable tanks are the ones from the newer Godot version. No old tank models, turrets or old tank mechanics were copied into this build.

The newer project's movement, combat, equipment/economy, tank visuals, audio and effects remain in place.

## Maps

The default Arena v3 remains at:

`client/scenes/maps/arena_editable.tscn`

Every additional `.tscn` placed directly in `client/scenes/maps/` becomes a selectable battle map automatically. A duplicate such as `arena_day.tscn` can reuse the same geometry/physics while changing lighting, environment or materials. See `UI_EDITING_GUIDE_RU.md` for map naming, previews and spawn-point conventions, and `ARENA_EDITOR_GUIDE_RU.md` for the existing Arena editing workflow.

## Run locally

### 1. Start the server

Windows:

```bat
start_server.bat
```

Linux/macOS:

```bash
./start_server.sh
```

Default UDP port: **9100**.

### 2. Start Godot

Open `client/project.godot` in Godot 4.x and run the project, or use:

```bat
run_client.bat
```

```bash
./run_client.sh
```

Flow: **login/register → battle list → create/select battle + map → join battle**.

## Controls

- `↑/↓` or `W/S` — forward/back
- `←/→` or `A/D` — differential hull steering
- `Z/X` — turret
- `Space` — fire
- `Page Up/Page Down` — camera elevation

## Server smoke test

```bash
python server/tests/smoke_test.py
python server/tests/map_autodiscovery_test.py
```

The first test verifies independent battle rooms and kill limits. The second temporarily drops a new `.tscn` into `client/scenes/maps`, verifies that the server discovers it automatically, creates a room on that map and joins it. Temporary files/accounts are restored when the tests exit.

## Conversion tools

The original reproducible Arena/tank conversion tooling remains under `tools/`, and the supplied Arena resources remain under `original_arena_v3/`.

## Editable Godot GUI scenes

This build moves the static 2D interface out of `client/scripts/main.gd` and into normal Godot scenes under:

`client/scenes/ui/`

Open `client/project.godot`, expand `res://scenes/ui/`, and edit the required `.tscn` in the **2D** workspace. The battle list row, garage item card and create-battle dialog are also scene templates, so dynamically created UI can be redesigned visually as well.

Container-managed visual elements are now wrapped in ordinary `Control` nodes ending in `Slot`; edit the real child inside the slot to get manual Position/Size controls. Every UI scene also includes an empty `FreeCanvas` for fully free positioning. Runtime code resolves functional nodes recursively by name, so visual nodes can be reparented without rewriting NodePaths.

For the exact scene map and safe-editing notes, see `UI_EDITING_GUIDE_RU.md`.

### First editor open

The package intentionally does not include `client/.godot/` (local import cache) or the old exported `.pck`. Open `client/project.godot` in Godot 4.7 and let the editor import the source assets once. This guarantees that the editable `.tscn` GUI scenes and the current source code are what you run.
