from pathlib import Path
import shutil
ROOT=Path.cwd()
FILES=[
    Path('client/assets/hulls/wasp_m0_remaster.glb'),
    Path('client/assets/turrets/smoky_m0_remaster.glb'),
    Path('client/assets/tank_textures/wasp_m0/normalmap.png'),
    Path('client/assets/tank_textures/wasp_m0/detail_normal.png'),
    Path('client/assets/tank_textures/smoky_m0/normalmap.png'),
    Path('client/assets/tank_textures/smoky_m0/detail_normal.png'),
]
for rel in FILES:
    dst=ROOT/rel
    bak=dst.with_name(dst.name+'.bak_v20_0_2')
    if bak.exists():
        shutil.copy2(bak,dst)
        print('RESTORED:',rel)
    else:
        print('NO BACKUP:',rel)
print('Rollback finished.')
