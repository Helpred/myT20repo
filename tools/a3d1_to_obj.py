#!/usr/bin/env python3
"""Minimal Alternativa3D A3D 1.0 -> OBJ converter for the Tanki 2.0 demo assets.

The parser follows the A3D v1 structures used by the historical alternativa3d_tools
Blender importer. It intentionally exports only the render object named ``turret``;
helper Box/muzzle/fmnt objects are retained only as metadata.
"""
from __future__ import annotations
import argparse, json, math, struct
from pathlib import Path

class Reader:
    def __init__(self, data: bytes): self.data, self.pos = data, 0
    def read(self, n: int) -> bytes:
        chunk = self.data[self.pos:self.pos+n]
        if len(chunk) != n: raise EOFError(f"Unexpected EOF at {self.pos}, wanted {n}")
        self.pos += n
        return chunk
    def u8(self): return self.read(1)[0]
    def u16_be(self): return struct.unpack('>H', self.read(2))[0]
    def u32_be(self): return struct.unpack('>I', self.read(4))[0]
    def u16_le(self): return struct.unpack('<H', self.read(2))[0]
    def f32_be(self): return struct.unpack('>f', self.read(4))[0]
    def f32_le(self): return struct.unpack('<f', self.read(4))[0]

def read_var_len(r: Reader) -> int:
    b = r.u8()
    if b < 0x80: return b
    if b < 0xC0: return ((b & 0x3F) << 8) | r.u8()
    return ((b & 0x3F) << 16) | (r.u8() << 8) | r.u8()

def read_string(r: Reader) -> str:
    return r.read(read_var_len(r)).decode('utf-8', 'replace').rstrip('\x00')

def read_null_mask(r: Reader) -> str:
    b = r.u8(); bits = f'{b:08b}'
    if bits[0] == '0':
        extra = {'00':0, '01':1, '10':2, '11':3}[bits[1:3]]
        mask = bits[3:]
        for _ in range(extra): mask += f'{r.u8():08b}'
        return mask
    if bits[1] == '0':
        count = int(bits[2:], 2)
    else:
        count = (int(bits[2:], 2) << 16) | (r.u8() << 8) | r.u8()
    return ''.join(f'{r.u8():08b}' for _ in range(count))

class A3D1:
    def __init__(self, data: bytes):
        self.r = Reader(data); self.mask = ''; self.mi = 0
        self.boxes=[]; self.geometries=[]; self.images=[]; self.maps=[]; self.materials=[]; self.objects=[]
    def bit(self) -> str:
        if self.mi >= len(self.mask): raise ValueError(f'Null mask exhausted at bit {self.mi}')
        b = self.mask[self.mi]; self.mi += 1; return b
    def opt(self, fn, default=None): return fn() if self.bit() == '0' else default
    def parse(self):
        if self.r.data[:1] != b'\x00': raise ValueError('This converter supports A3D 1.0 only')
        self.r.pos = 4
        self.mask = read_null_mask(self.r)
        for arr, fn in [
            (self.boxes,self._box),(self.geometries,self._geometry),(self.images,self._image),
            (self.maps,self._map),(self.materials,self._material),(self.objects,self._object)]:
            if self.bit() == '0':
                for _ in range(read_var_len(self.r)): arr.append(fn())
        if self.r.pos != len(self.r.data):
            raise ValueError(f'Parser ended at {self.r.pos}/{len(self.r.data)} bytes')
        return self
    def _box(self):
        values=self.opt(lambda:[self.r.f32_be() for _ in range(read_var_len(self.r))], [])
        return {'values':values, 'id':self.opt(self.r.u32_be,0)}
    def _index_buffer(self):
        indices=self.opt(lambda:[self.r.u16_le() for _ in range(read_var_len(self.r)//2)], [])
        return {'indices':indices, 'count':self.opt(self.r.u32_be,0)}
    def _vertex_buffer(self):
        attrs=self.opt(lambda:[self.r.u8() for _ in range(read_var_len(self.r))], [])
        values=self.opt(lambda:[self.r.f32_le() for _ in range(read_var_len(self.r)//4)], [])
        return {'attrs':attrs, 'values':values, 'count':self.opt(self.r.u16_be,0)}
    def _geometry(self):
        gid=self.opt(self.r.u32_be,0)
        # A3D1's nested complex values reuse their first field's mask bit; there is no
        # additional presence bit consumed here. This mirrors the original importer.
        ib=None
        if self.mask[self.mi] == '0': ib=self._index_buffer()
        vbs=[]
        if self.mask[self.mi] == '0':
            for _ in range(read_var_len(self.r)): vbs.append(self._vertex_buffer())
        return {'id':gid,'index':ib,'vertex_buffers':vbs}
    def _image(self):
        iid=self.r.u32_be()  # id is mandatory in v1
        return {'id':iid,'url':self.opt(lambda:read_string(self.r),'')}
    def _map(self):
        return {
            'channel':self.opt(self.r.u16_be,0),'id':self.opt(self.r.u32_be,0),
            'image_id':self.opt(self.r.u32_be,0),'u_offset':self.opt(self.r.f32_be,0.0),
            'u_scale':self.opt(self.r.f32_be,0.0),'v_offset':self.opt(self.r.f32_be,0.0),
            'v_scale':self.opt(self.r.f32_be,0.0)}
    def _material(self):
        return {'diffuse':self.opt(self.r.u32_be,None),'gloss':self.opt(self.r.u32_be,None),
                'id':self.opt(self.r.u32_be,0),'light':self.opt(self.r.u32_be,None),
                'normal':self.opt(self.r.u32_be,None),'opacity':self.opt(self.r.u32_be,None),
                'specular':self.opt(self.r.u32_be,None)}
    def _surface(self):
        return {'begin':self.opt(self.r.u32_be,0),'material':self.opt(self.r.u32_be,None),
                'triangles':self.opt(self.r.u32_be,0)}
    def _surfaces(self):
        if self.mask[self.mi] != '0': return []
        return [self._surface() for _ in range(read_var_len(self.r))]
    def _transform(self): return [self.r.f32_be() for _ in range(12)]
    def _object(self):
        return {'box':self.opt(self.r.u32_be,None),'geometry':self.opt(self.r.u32_be,None),
                'id':self.opt(self.r.u32_be,0),'name':self.opt(lambda:read_string(self.r),''),
                'parent':self.opt(self.r.u32_be,None),'surfaces':self._surfaces(),
                'transform':self.opt(self._transform,None),'visible':self.opt(self.r.u8,1)}

def comps(attr: int) -> int:
    return {0:3,1:3,2:4,3:3,4:4,5:2,6:1}.get(attr,0)

def convert_vec(x,y,z, scale=0.01):
    # Alternativa/3ds Max data is Z-up, forward +Y. Godot is Y-up, gameplay forward -Z.
    return (x*scale, z*scale, -y*scale)

def decode_vertices(vb):
    attrs=vb['attrs']; stride=sum(comps(a) for a in attrs)
    if stride <= 0 or len(vb['values']) < vb['count']*stride:
        raise ValueError(f'Unsupported vertex buffer attrs={attrs} stride={stride}')
    out=[]; values=vb['values']; p=0
    for _ in range(vb['count']):
        item={}
        for a in attrs:
            n=comps(a); val=values[p:p+n]; p+=n
            item[a]=val
        out.append(item)
    return out

def transform_position_from_matrix(m):
    if not m: return (0.0,0.0,0.0)
    # row-major 3x4 matrix: translation is d,h,l.
    return convert_vec(m[3],m[7],m[11])

def export_turret(src: Path, obj_path: Path, metadata_path: Path):
    scene=A3D1(src.read_bytes()).parse()
    by_gid={g['id']:g for g in scene.geometries}
    render=next((o for o in scene.objects if o['name'].lower()=='turret'), None)
    if render is None: raise ValueError('No object named turret')
    geom=by_gid[render['geometry']]
    if not geom['vertex_buffers']: raise ValueError('Turret has no vertex buffer')
    vb=geom['vertex_buffers'][0]; verts=decode_vertices(vb)
    indices=geom['index']['indices']
    # Export exactly the render object's surfaces (normally one complete surface).
    ranges=[]
    for s in render['surfaces']:
        begin=s['begin']; end=begin+s['triangles']*3; ranges.extend(indices[begin:end])
    if not ranges: ranges=indices

    obj_path.parent.mkdir(parents=True, exist_ok=True)
    lines=['# Tanki Online 2.0 Demo turret converted from A3D 1.0','o turret']
    has_uv=5 in vb['attrs']; has_n=1 in vb['attrs']
    for v in verts:
        x,y,z=convert_vec(*v[0]); lines.append(f'v {x:.7f} {y:.7f} {z:.7f}')
    if has_uv:
        for v in verts:
            u,w=v[5][:2]; lines.append(f'vt {u:.7f} {1.0-w:.7f}')
    if has_n:
        for v in verts:
            x,y,z=convert_vec(*v[1], scale=1.0)
            ln=math.sqrt(x*x+y*y+z*z) or 1.0
            lines.append(f'vn {x/ln:.7f} {y/ln:.7f} {z/ln:.7f}')
    lines.append('s 1')
    for i in range(0,len(ranges)-2,3):
        ids=[ranges[i]+1,ranges[i+1]+1,ranges[i+2]+1]
        def fmt(q):
            if has_uv and has_n: return f'{q}/{q}/{q}'
            if has_uv: return f'{q}/{q}'
            if has_n: return f'{q}//{q}'
            return str(q)
        lines.append('f '+' '.join(fmt(q) for q in ids))
    obj_path.write_text('\n'.join(lines)+'\n', encoding='utf-8')

    helpers={o['name']:transform_position_from_matrix(o['transform']) for o in scene.objects if o['name'].lower()!='turret'}
    muzzle=next((helpers[k] for k in helpers if k.lower().startswith('muzzle')), None)
    barrel=next((helpers[k] for k in helpers if k.lower().startswith('barrel')), None)
    meta={'source':str(src.name),'vertex_count':len(verts),'triangle_count':len(ranges)//3,
          'muzzle':muzzle,'barrel_helper':barrel,'helpers':helpers}
    metadata_path.write_text(json.dumps(meta,indent=2),encoding='utf-8')
    return meta

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('src',type=Path); ap.add_argument('obj',type=Path); ap.add_argument('--meta',type=Path)
    a=ap.parse_args(); meta=a.meta or a.obj.with_suffix('.json')
    print(json.dumps(export_turret(a.src,a.obj,meta),indent=2))
if __name__=='__main__': main()
