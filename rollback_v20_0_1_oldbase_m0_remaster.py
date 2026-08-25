from pathlib import Path
import shutil
ROOT=Path.cwd()
restored=[]
for rel in ['client/scripts/tank.gd','server/data/loadout_catalog.json']:
    p=ROOT/rel
    b=p.with_name(p.name+'.bak_v20_0_1_m0_remaster')
    if b.exists():
        shutil.copy2(b,p); restored.append(rel)
print('Restored:', ', '.join(restored) if restored else 'nothing (backup not found)')
print('Remaster asset files are left in place; they are harmless when catalog no longer references them.')
