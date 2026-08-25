#!/usr/bin/env python3
"""Build the demo-style painted tank albedo from decoded ATF maps.

This pass intentionally keeps the camouflage pattern smaller than the previous
prototype (the old build stretched one 256x256 colormap over the full 1024 atlas).
It also adds restrained edge wear and grime without painting over the baked
mechanical detail present in diffuse.atf.
"""
from pathlib import Path
import numpy as np
import zlib
from PIL import Image, ImageFilter

PROJECT=Path(__file__).resolve().parent.parent
TEX=PROJECT/'client/assets/tank_textures'
COL=PROJECT/'client/assets/colormaps'
PAIRS={
    'wasp_m2':'flora.jpg',
    'smoky_m2':'flora.jpg',
    'viking_m1':'swamp.jpg',
    'firebird_m1':'swamp.jpg',
    'mamont_m3':'winter.jpg',
    'thunder_m3':'winter.jpg',
}
CAMO_REPEAT = 2.55


def smoothstep(a,b,x):
    t=np.clip((x-a)/(b-a),0,1)
    return t*t*(3-2*t)


def tiled_colormap(path: Path, w: int, h: int) -> Image.Image:
    src=Image.open(path).convert('RGB')
    # Repeating the color map gives substantially smaller blotches than the old
    # full-atlas stretch. Offset alternating tiles to avoid a visible checker.
    tile=max(64, int(round(max(w,h)/CAMO_REPEAT)))
    src=src.resize((tile,tile),Image.Resampling.LANCZOS)
    canvas=Image.new('RGB',(w,h))
    for y in range(-tile,h+tile,tile):
        row=(y//tile)&1
        for x in range(-tile,w+tile,tile):
            xx=x + (tile//2 if row else 0)
            canvas.paste(src,(xx,y))
    return canvas


def low_frequency_noise(w:int,h:int,seed:int)->np.ndarray:
    rng=np.random.default_rng(seed)
    sw=max(8,w//64); sh=max(8,h//64)
    small=(rng.random((sh,sw))*255).astype(np.uint8)
    im=Image.fromarray(small,'L').resize((w,h),Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(max(1,w/256)))
    return np.asarray(im,dtype=np.float32)/255.0


def build(name, coloring_name):
    folder=TEX/name
    base=np.asarray(Image.open(folder/'diffuse.png').convert('RGB'),dtype=np.float32)/255.0
    surface=np.asarray(Image.open(folder/'surface.png').convert('RGB'),dtype=np.float32)/255.0
    h,w=base.shape[:2]
    paint=np.asarray(tiled_colormap(COL/coloring_name,w,h),dtype=np.float32)/255.0

    # Surface red is the paintable area in these recovered demo assets. Keep
    # non-painted rubber/mechanism areas close to the original diffuse.
    mask=smoothstep(0.18,0.72,surface[...,0])[...,None]
    lum=(paint[...,0]*0.2126+paint[...,1]*0.7152+paint[...,2]*0.0722)
    mean=max(float(lum.mean()),0.08)
    chroma=paint/np.maximum(lum[...,None],0.10)
    base_l=(base[...,0]*0.2126+base[...,1]*0.7152+base[...,2]*0.0722)
    brightness=np.clip(0.42+0.68*(lum[...,None]/mean),0.28,1.35)
    colored=np.clip(chroma*base_l[...,None]*brightness,0,1)
    strength=0.76  # less overwhelming camouflage than v4-v9
    out=np.clip(base*(1-mask*strength)+colored*(mask*strength),0,1)

    # Edge wear: gradient of original diffuse catches panel borders/bolts without
    # inventing arbitrary scratches across blank paint. A small fraction exposes
    # cool steel highlights.
    gy,gx=np.gradient(base_l)
    edge=np.sqrt(gx*gx+gy*gy)
    p96=float(np.percentile(edge,96.0))
    if p96 > 1e-6:
        edge=np.clip(edge/p96,0,1)
    edge=smoothstep(0.32,0.88,edge) * mask[...,0]
    # Avoid turning every bright texture edge into bare metal.
    edge*=smoothstep(0.12,0.70,base_l)
    steel=np.array([0.48,0.50,0.49],dtype=np.float32)
    wear=(edge*0.15)[...,None]
    out=out*(1-wear)+steel*wear

    # Grime/dust: subtle low-frequency accumulation, stronger in already-dark
    # recesses and on non-pristine painted areas. This is deliberately subdued.
    noise=low_frequency_noise(w,h,zlib.crc32(name.encode("utf8")))
    recess=smoothstep(0.26,0.72,1.0-base_l)
    grime=np.clip((0.30+0.70*noise)*recess*(0.35+0.65*mask[...,0]),0,1)
    grime=(grime*0.10)[...,None]
    grime_color=np.array([0.105,0.095,0.075],dtype=np.float32)
    out=out*(1-grime)+grime_color*grime

    # Mild gamma lift keeps old baked diffuse from becoming too dark under PBR.
    out=np.power(np.clip(out,0,1),0.94)
    Image.fromarray((out*255+0.5).astype(np.uint8),'RGB').save(folder/'albedo.png',optimize=True)
    Image.fromarray((np.clip(edge,0,1)*255+0.5).astype(np.uint8),'L').save(folder/'wear_mask.png',optimize=True)
    print(name,'->',folder/'albedo.png')

for n,c in PAIRS.items():
    build(n,c)
