# V8 weapon effects

This build finishes the first visual-effects pass before work moves to Arena v3.

## Original demo textures

The preserved ATF DXT1 sprite sheets in `original_arena_v3/data/dxt1/images/` are decoded to RGBA PNG files in `client/assets/effects/`.

- `smoky_rgba.png` — 8x8 sheet used for muzzle flash, smoke and impact/explosion frames.
- `firebird_rgba.png` — 8x8 sheet used for the continuous flamethrower stream.
- `fire_rgba.png` — decoded and preserved for later VFX matching.

The conversion is reproducible with `tools/decode_effect_textures.py`.

## Smoky

A shot now creates a brief animated muzzle flash, a drifting muzzle-smoke puff, an animated impact burst and secondary smoke at the hit point. A very short local light flash is used at the muzzle and impact instead of the old glowing sphere effect.

## Thunder

Thunder uses a larger/slower version of the preserved explosion/smoke frames, with a stronger impact flash and denser smoke plume.

## Firebird

The old chain of procedural orange spheres is removed. While firing, the client emits animated billboard sprites from the real Firebird sheet. Each flame packet travels forward, expands and fades, leaving a continuous stream; the muzzle also has a small flickering point light. The same `firing` state already sent in snapshots drives the effect on remote tanks.

## Networking

Discrete shot events continue to be relayed by the Python server with the authoritative slot/weapon name, so remote clients choose the same Smoky/Thunder VFX as the shooter. Firebird is continuous and continues to use the synchronized `firing` state.

## Validation

The Python UDP server smoke test passes after these changes (`hello / exclusive slot / snapshot / reliable shot`). Godot itself is not installed in the build container, so the new Sprite3D effect scripts require the same editor-side import/run validation as previous client revisions.
