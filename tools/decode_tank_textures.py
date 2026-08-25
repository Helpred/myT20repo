#!/usr/bin/env python3
from pathlib import Path
import importlib.util

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parent
spec=importlib.util.spec_from_file_location('atf', HERE/'atf_dxt1_to_png.py')
atf=importlib.util.module_from_spec(spec); spec.loader.exec_module(atf)
SRC=PROJECT/'original_arena_v3/data/dxt1/tanks'
DST=PROJECT/'client/assets/tank_textures'
items={
 'wasp_m2': SRC/'hulls/wasp/m2',
 'viking_m1': SRC/'hulls/viking/m1',
 'mamont_m3': SRC/'hulls/mamont/m3',
 'smoky_m2': SRC/'turrets/smoky/m2',
 'firebird_m1': SRC/'turrets/firebird/m1',
 'thunder_m3': SRC/'turrets/thunder/m3',
}
for key,folder in items.items():
    for p in sorted(folder.glob('*.atf')):
        if p.name=='shadow.atf':
            continue
        out=DST/key/(p.stem+'.png')
        if out.exists():
            print(f'skip {out.relative_to(PROJECT)}')
            continue
        w,h,m=atf.decode_atf(p,out)
        print(f'{key}/{p.name} -> {out.relative_to(PROJECT)} ({w}x{h})')
