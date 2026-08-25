# Arena / tank-finish v10

- Added Arena v3 as a selectable multiplayer map room.
- Kept Test Polygon as a second selectable room.
- Converted original Arena A3D visual geometry to glTF.
- Decoded original Arena ATF textures.
- Preserved baked lightmap information by sampling the second UV channel into glTF vertex color.
- Converted original physics.a3d to a static trimesh collision OBJ.
- Converted original skybox to a panorama and retained lights.dae.
- Rebuilt tank camouflage at ~2.55x smaller visual pattern scale.
- Added subtle edge wear and grime to tank albedos.
- Added roughness/metallic/detail-normal material maps and differentiated tracks from painted metal.
- Added persistent soot cards at weapon muzzles.
- Enlarged Thunder muzzle/impact VFX again.
- Server now maintains separate slot/snapshot/shot rooms for Arena and Test Polygon.
