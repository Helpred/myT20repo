# FX / Materials v9

Changes in this pass:

- Copied the sprite-sheet based VFX runtime (`sheet_effect.gd`) and original decoded effect atlases into the main project.
- Scaled up **Smoky** muzzle flash, smoke trail, impact blast, and impact smoke so they read closer to the original game at camera distance.
- Scaled up **Thunder** muzzle flash and impact explosion significantly, with larger lingering smoke and stronger flash lights.
- Reworked **Firebird** into a larger layered flame plume using the original `fire_rgba` + `firebird_rgba` atlases, with bigger core flame, secondary billows, and smoke rolls above the stream.
- Added generated **roughness** and **metallic** maps for all hulls/turrets/tracks under `client/assets/tank_textures/*`.
- Upgraded tank materials to use:
  - albedo textures
  - generated roughness maps
  - generated metallic maps
  - decoded normal maps already present in the asset dump
- Tuned hull/turret materials to read more like painted metal instead of plastic; tracks remain rougher/more matte.

Primary files changed:
- `client/scripts/tank.gd`
- `client/scripts/sheet_effect.gd`
- `client/assets/effects/*`
- `client/assets/tank_textures/*/roughness.png`
- `client/assets/tank_textures/*/metallic.png`
- `client/assets/tank_textures/*/tracks_roughness.png`
- `client/assets/tank_textures/*/tracks_metallic.png`
