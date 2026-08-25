#!/usr/bin/env python3
from __future__ import annotations
import json, math, struct, sys
from pathlib import Path
from collections import defaultdict
import numpy as np
from PIL import Image

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from a3d_v1_exact import A3D1Exact, decode_vertex_buffer, decode_indices

ROOT=HERE.parent
EXTRACT=ROOT/'_arena_build_source'
OUT=ROOT/'client/assets/maps/arena'
TEX=OUT/'textures'

def transform_pos(v,m):
    x,y,z=v
    if m:
        x,y,z=(m[0]*x+m[1]*y+m[2]*z+m[3],
               m[4]*x+m[5]*y+m[6]*z+m[7],
               m[8]*x+m[9]*y+m[10]*z+m[11])
    return np.array((x*0.01,z*0.01,-y*0.01),dtype=np.float32)

def uv_apply(uv, mp):
    if uv is None:return (0.0,0.0)
    u,v=float(uv[0]),float(uv[1])
    us=1.0 if mp.get('u_scale') is None else float(mp['u_scale'])
    vs=1.0 if mp.get('v_scale') is None else float(mp['v_scale'])
    uo=0.0 if mp.get('u_offset') is None else float(mp['u_offset'])
    vo=0.0 if mp.get('v_offset') is None else float(mp['v_offset'])
    u=u*us+uo; v=v*vs+vo
    return (u,1.0-v)

def source_uv(v, channel:int):
    # A3D channels are 1-based. The Arena geometry carries uv0 + uv1.
    return v.get(f'uv{max(0,channel-1)}',v.get('uv0',(0.0,0.0)))

def sample_image(arr, uv):
    h,w=arr.shape[:2]
    u=max(0.0,min(1.0,float(uv[0]))); v=max(0.0,min(1.0,float(uv[1])))
    x=int(round(u*(w-1))); y=int(round(v*(h-1)))
    return arr[y,x].astype(np.float32)/255.0

def stem_for_url(url:str):
    stem=Path(url.rstrip('\x00')).stem.lower()
    # Normal map images are referenced by A3D but aren't separate blobs in this TARA.
    if stem.endswith('_nrm') or stem.endswith('_map_nrm'): return None
    return stem

def parse_scene(path:Path):return A3D1Exact(path.read_bytes()).parse()

def compute_normals(positions, indices):
    pos=np.asarray(positions,dtype=np.float32)
    norm=np.zeros_like(pos)
    for i in range(0,len(indices)-2,3):
        a,b,c=indices[i:i+3]
        e1=pos[b]-pos[a]; e2=pos[c]-pos[a]
        n=np.cross(e1,e2)
        l=float(np.linalg.norm(n))
        if l>1e-9:n/=l
        norm[a]+=n;norm[b]+=n;norm[c]+=n
    lens=np.linalg.norm(norm,axis=1); lens[lens<1e-9]=1
    norm/=lens[:,None]
    return norm

def make_bims_rgba():
    d=Image.open(TEX/'bims.png').convert('RGB')
    o=Image.open(TEX/'bims_opc.png').convert('L').resize(d.size,Image.Resampling.BILINEAR)
    rgba=d.convert('RGBA'); rgba.putalpha(o); rgba.save(TEX/'bims_rgba.png',optimize=True)

def build_visual():
    scene=parse_scene(EXTRACT/'arena.a3d')
    imgs={x['id']:x['url'] for x in scene.images}
    maps={x['id']:x for x in scene.maps}
    mats={x['id']:x for x in scene.materials}
    geoms={x['id']:x for x in scene.geometries}
    image_cache={}
    def decoded(stem):
        if not stem:return None
        p=TEX/(stem+'.png')
        if not p.exists():return None
        if stem not in image_cache:image_cache[stem]=np.asarray(Image.open(p).convert('RGB'))
        return image_cache[stem]

    groups=defaultdict(lambda:{'pos':[],'nrm':[],'uv':[],'col':[]})
    material_meta={}

    for obj in scene.objects:
        geom=geoms.get(obj['geometry'])
        if not geom or not geom['vertex_buffers'] or not geom['index']:continue
        verts=decode_vertex_buffer(geom['vertex_buffers'][0])
        indices=decode_indices(geom['index'])
        pos=[transform_pos(v[0],obj['transform']) for v in verts]
        normals=compute_normals(pos,indices)
        for surf in obj['surfaces']:
            mat=mats.get(surf['material'])
            if not mat:continue
            dmap=maps.get(mat['diffuse']); lmap=maps.get(mat['light'])
            dstem=stem_for_url(imgs.get(dmap['image_id'],'') if dmap else '')
            lstem=stem_for_url(imgs.get(lmap['image_id'],'') if lmap else '')
            # Group on the diffuse binding. Lightmap stays per-vertex, allowing 923 A3D materials
            # to collapse into ~60 Godot draw materials without throwing baked lighting away.
            key=(dstem, dmap['channel'] if dmap else 1,
                 dmap.get('u_offset') if dmap else 0.0,dmap.get('u_scale') if dmap else 1.0,
                 dmap.get('v_offset') if dmap else 0.0,dmap.get('v_scale') if dmap else 1.0)
            material_meta[key]={'stem':dstem,'alpha':False}
            g=groups[key]
            start=surf['begin']; end=start+surf['triangles']*3
            lm_img=decoded(lstem)
            for idx in indices[start:end]:
                v=verts[idx]
                g['pos'].append(pos[idx]); g['nrm'].append(normals[idx])
                g['uv'].append(uv_apply(source_uv(v,dmap['channel'] if dmap else 1),dmap or {}))
                light=np.array([1.0,1.0,1.0],dtype=np.float32)
                if lm_img is not None and lmap is not None:
                    luv=uv_apply(source_uv(v,lmap['channel']),lmap)
                    s=sample_image(lm_img,luv)
                    # Preserve dark baked occlusion but keep enough ambient response for Godot PBR.
                    light=np.clip(0.20+s*1.02,0.12,1.15)
                g['col'].append(light)

    # Add the original translucent beam meshes from beams.a3d.
    beams=parse_scene(EXTRACT/'beams.a3d')
    bgeoms={x['id']:x for x in beams.geometries}
    bkey=('__bims_rgba__',1,0.0,1.0,0.0,1.0)
    material_meta[bkey]={'stem':'bims_rgba','alpha':True}
    bg=groups[bkey]
    for obj in beams.objects:
        geom=bgeoms.get(obj['geometry'])
        if not geom or not geom['vertex_buffers'] or not geom['index']:continue
        verts=decode_vertex_buffer(geom['vertex_buffers'][0]); inds=decode_indices(geom['index'])
        pos=[transform_pos(v[0],obj['transform']) for v in verts]; norms=compute_normals(pos,inds)
        for surf in obj['surfaces']:
            for idx in inds[surf['begin']:surf['begin']+surf['triangles']*3]:
                bg['pos'].append(pos[idx]);bg['nrm'].append(norms[idx]);bg['uv'].append(uv_apply(source_uv(verts[idx],1),{}));bg['col'].append((1.0,1.0,1.0))

    OUT.mkdir(parents=True,exist_ok=True)
    bin_data=bytearray(); buffer_views=[]; accessors=[]
    def align4():
        while len(bin_data)%4:bin_data.append(0)
    def add_accessor(array,component_type,type_name,target=None,normalized=False):
        align4(); offset=len(bin_data)
        arr=np.asarray(array)
        raw=arr.tobytes(order='C');bin_data.extend(raw)
        bv={'buffer':0,'byteOffset':offset,'byteLength':len(raw)}
        if target is not None:bv['target']=target
        bvi=len(buffer_views);buffer_views.append(bv)
        count=len(arr); acc={'bufferView':bvi,'componentType':component_type,'count':count,'type':type_name}
        if normalized:acc['normalized']=True
        if type_name=='VEC3' and component_type==5126 and count and target==34962:
            # only positions really need bounds; normals/colors don't hurt if omitted
            pass
        ai=len(accessors);accessors.append(acc);return ai

    # register texture/image entries lazily
    images=[];textures=[];texture_by_stem={}
    def texture_index(stem):
        if not stem:return None
        if stem in texture_by_stem:return texture_by_stem[stem]
        uri='textures/'+stem+'.png'
        if not (OUT/uri).exists():return None
        images.append({'uri':uri,'name':stem}); textures.append({'source':len(images)-1})
        ti=len(textures)-1;texture_by_stem[stem]=ti;return ti

    materials=[]; material_index={}
    for key,meta in material_meta.items():
        stem=meta['stem']; name='arena_'+str(stem or 'plain')+'_'+str(len(materials))
        ti=texture_index(stem)
        metallic=0.12 if stem and ('metall' in stem or 'armatur' in stem or 'turrel' in stem) else 0.0
        rough=0.70 if metallic>0 else (0.92 if stem and ('grass' in stem or 'land_' in stem or 'stone' in stem) else 0.82)
        pbr={'baseColorFactor':[1,1,1,1],'metallicFactor':metallic,'roughnessFactor':rough}
        if ti is not None:pbr['baseColorTexture']={'index':ti}
        gm={'name':name,'pbrMetallicRoughness':pbr,'doubleSided':True}
        if meta.get('alpha'):
            gm['alphaMode']='BLEND';gm['alphaCutoff']=0.08
        if stem and stem.startswith('light_') and ti is not None:
            gm['emissiveTexture']={'index':ti};gm['emissiveFactor']=[0.8,0.65,0.42]
        material_index[key]=len(materials);materials.append(gm)

    primitives=[]
    total_vertices=0
    for key,g in groups.items():
        if not g['pos']:continue
        pos=np.asarray(g['pos'],dtype='<f4');nrm=np.asarray(g['nrm'],dtype='<f4');uv=np.asarray(g['uv'],dtype='<f4');col=np.asarray(g['col'],dtype='<f4')
        a_pos=add_accessor(pos,5126,'VEC3',34962); accessors[a_pos]['min']=pos.min(axis=0).tolist();accessors[a_pos]['max']=pos.max(axis=0).tolist()
        a_nrm=add_accessor(nrm,5126,'VEC3',34962);a_uv=add_accessor(uv,5126,'VEC2',34962);a_col=add_accessor(col,5126,'VEC3',34962)
        primitives.append({'attributes':{'POSITION':a_pos,'NORMAL':a_nrm,'TEXCOORD_0':a_uv,'COLOR_0':a_col},'material':material_index[key],'mode':4})
        total_vertices+=len(pos)
    (OUT/'arena_visual.bin').write_bytes(bin_data)
    gltf={'asset':{'version':'2.0','generator':'Tanki2 Godot A3D converter'},'scene':0,
          'scenes':[{'nodes':[0]}],'nodes':[{'mesh':0,'name':'ArenaV3Original'}],
          'meshes':[{'name':'ArenaV3Original','primitives':primitives}],
          'buffers':[{'uri':'arena_visual.bin','byteLength':len(bin_data)}],
          'bufferViews':buffer_views,'accessors':accessors,'materials':materials,'images':images,'textures':textures,
          'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}]}
    for t in gltf['textures']:t['sampler']=0
    (OUT/'arena_visual.gltf').write_text(json.dumps(gltf,separators=(',',':')),encoding='utf8')
    print(f'visual: {len(primitives)} primitives, {len(materials)} materials, {total_vertices} vertices, {len(bin_data)/1048576:.1f} MiB bin')


def build_collision():
    scene=parse_scene(EXTRACT/'physics.a3d'); geoms={x['id']:x for x in scene.geometries}
    lines=['# Arena v3 original physics converted from A3D','o ArenaPhysics']; voff=0; tris=0
    for obj in scene.objects:
        geom=geoms.get(obj['geometry'])
        if not geom or not geom['vertex_buffers'] or not geom['index']:continue
        verts=decode_vertex_buffer(geom['vertex_buffers'][0]);inds=decode_indices(geom['index'])
        pos=[transform_pos(v[0],obj['transform']) for v in verts]
        for v in pos:lines.append(f'v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}')
        used=[]
        for surf in obj['surfaces']:
            used.extend(inds[surf['begin']:surf['begin']+surf['triangles']*3])
        for i in range(0,len(used)-2,3):
            a,b,c=used[i]+1+voff,used[i+1]+1+voff,used[i+2]+1+voff
            lines.append(f'f {a} {b} {c}');tris+=1
        voff+=len(pos)
    (OUT/'arena_physics.obj').write_text('\n'.join(lines)+'\n',encoding='utf8')
    print(f'collision: {voff} vertices, {tris} triangles')

if __name__=='__main__':
    if not EXTRACT.exists():
        raise SystemExit(f'Missing extracted TARA source at {EXTRACT}')
    make_bims_rgba();build_visual();build_collision()
