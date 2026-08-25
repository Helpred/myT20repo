#!/usr/bin/env python3
"""Exact reader for the Alternativa Protocol A3D v1 files used by Tanki 2.0 demo.
The field optionality follows the recovered protocol codecs.
"""
from __future__ import annotations
import struct

class Reader:
    def __init__(self,data:bytes): self.data=data; self.pos=0
    def read(self,n:int)->bytes:
        out=self.data[self.pos:self.pos+n]
        if len(out)!=n: raise EOFError(f'EOF at {self.pos}, wanted {n}')
        self.pos+=n; return out
    def u8(self): return self.read(1)[0]
    def u16_be(self): return struct.unpack('>H',self.read(2))[0]
    def u32_be(self): return struct.unpack('>I',self.read(4))[0]
    def i32_be(self): return struct.unpack('>i',self.read(4))[0]
    def f32_be(self): return struct.unpack('>f',self.read(4))[0]

def read_length(r:Reader)->int:
    a=r.u8()
    if a<0x80:return a
    b=r.u8()
    if (a&0x40)==0:return ((a&0x3f)<<8)|b
    c=r.u8(); return ((a&0x3f)<<16)|(b<<8)|c

def read_null_map(r:Reader)->list[bool]:
    first=r.u8()
    if first & 0x80:
        head=first&0x3f
        if first&0x40:
            n=(head<<16)|(r.u8()<<8)|r.u8()
        else:n=head
        raw=r.read(n); bit_count=n*8
    else:
        extra=(first&0x60)>>5
        raw=[(first<<3)&0xff]
        if extra>=1:
            b=r.u8(); raw[0]|=b>>5; raw.append((b<<3)&0xff)
        if extra>=2:
            c=r.u8(); raw[1]|=c>>5; raw.append((c<<3)&0xff)
        if extra>=3:
            d=r.u8(); raw[2]|=d>>5; raw.append((d<<3)&0xff)
        raw=bytes(raw); bit_count=5+8*extra
    bits=[]
    for byte in raw:
        bits.extend(bool(byte&(1<<(7-i))) for i in range(8))
    return bits[:bit_count]

class A3D1Exact:
    def __init__(self,data:bytes):
        self.r=Reader(data); self.bits=[]; self.bi=0
        self.boxes=[];self.geometries=[];self.images=[];self.maps=[];self.materials=[];self.objects=[]
    def bit(self)->bool:
        if self.bi>=len(self.bits):raise ValueError('optional map exhausted')
        v=self.bits[self.bi];self.bi+=1;return v
    def optional(self,fn,default=None): return default if self.bit() else fn()
    def collection(self,fn):
        if self.bit():return None
        return [fn() for _ in range(read_length(self.r))]
    def oid(self):return self.optional(self.r.u32_be,None)
    def string(self):return self.optional(lambda:self.r.read(read_length(self.r)).decode('utf-8','replace').rstrip('\x00'),None)
    def byte_array(self):return self.optional(lambda:self.r.read(read_length(self.r)),None)
    def parse(self):
        if self.r.u8()!=0: raise ValueError('only A3D v1 supported')
        self.r.pos=4; self.bits=read_null_map(self.r)
        self.boxes=self.collection(self._box) or []
        self.geometries=self.collection(self._geometry) or []
        self.images=self.collection(self._image) or []
        self.maps=self.collection(self._map) or []
        self.materials=self.collection(self._material) or []
        self.objects=self.collection(self._object) or []
        if self.r.pos!=len(self.r.data):raise ValueError(f'parser ended at {self.r.pos}/{len(self.r.data)}')
        return self
    def _box(self):return {'values':self.collection(self.r.f32_be) or [],'id':self.oid()}
    def _index_buffer(self):return {'data':self.byte_array() or b'','count':self.r.i32_be()}
    def _vertex_buffer(self):return {'attrs':self.collection(self.r.u8) or [],'data':self.byte_array() or b'','count':self.r.u16_be()}
    def _geometry(self):return {'id':self.oid(),'index':self.optional(self._index_buffer,None),'vertex_buffers':self.collection(self._vertex_buffer) or []}
    def _image(self):return {'id':self.oid(),'url':self.string() or ''}
    def _map(self):return {'channel':self.r.u16_be(),'id':self.oid(),'image_id':self.oid(),'u_offset':self.optional(self.r.f32_be,None),'u_scale':self.optional(self.r.f32_be,None),'v_offset':self.optional(self.r.f32_be,None),'v_scale':self.optional(self.r.f32_be,None)}
    def _material(self):return {'diffuse':self.oid(),'gloss':self.oid(),'id':self.oid(),'light':self.oid(),'normal':self.oid(),'opacity':self.oid(),'specular':self.oid()}
    def _surface(self):return {'begin':self.r.i32_be(),'material':self.oid(),'triangles':self.r.i32_be()}
    def _transformation(self):
        # A3DTransformation contains an optional A3DMatrix; the matrix has 12 mandatory floats.
        if self.bit():return None
        return [self.r.f32_be() for _ in range(12)]
    def _object(self):
        return {'box':self.oid(),'geometry':self.oid(),'id':self.oid(),'name':self.string() or '',
                'parent':self.oid(),'surfaces':self.collection(self._surface) or [],
                'transform':self.optional(self._transformation,None),'visible':self.optional(lambda:self.r.u8()!=0,None)}

def decode_vertex_buffer(vb:dict):
    """Return list of dicts. Repeated TEXCOORD attribute 5 becomes uv0/uv1/etc."""
    comps={0:3,1:3,2:4,3:3,4:4,5:2,6:1}
    stride=sum(comps.get(a,0) for a in vb['attrs'])
    vals=struct.unpack('<%df'%(len(vb['data'])//4),vb['data']) if vb['data'] else ()
    if stride<=0 or len(vals)<vb['count']*stride:raise ValueError(f'bad vertex buffer {vb["attrs"]}')
    out=[];p=0
    for _ in range(vb['count']):
        d={}; uv_i=0
        for a in vb['attrs']:
            n=comps[a]; v=vals[p:p+n];p+=n
            if a==5:
                d[f'uv{uv_i}']=v;uv_i+=1
            else:d[a]=v
        out.append(d)
    return out

def decode_indices(ib:dict):
    raw=ib['data']; return list(struct.unpack('<%dH'%(len(raw)//2),raw)) if raw else []
