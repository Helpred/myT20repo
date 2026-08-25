#!/usr/bin/env python3
"""Extract Alternativa .tara container used by Arena v3.
Format observed in the supplied demo: BE u32 count, then entries of
BE u16 filename length + UTF-8 name + BE u32 payload size, followed by payloads.
"""
from pathlib import Path
import argparse, struct

def extract(source: Path, out: Path):
    data=source.read_bytes(); off=0
    count=struct.unpack_from(">I",data,off)[0]; off+=4
    entries=[]
    for _ in range(count):
        n=struct.unpack_from(">H",data,off)[0]; off+=2
        name=data[off:off+n].decode("utf-8"); off+=n
        size=struct.unpack_from(">I",data,off)[0]; off+=4
        entries.append((name,size))
    out.mkdir(parents=True,exist_ok=True)
    for name,size in entries:
        blob=data[off:off+size]; off+=size
        target=out/name; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(blob)
        print(f"{size:9d}  {name}")
    if off != len(data):
        raise ValueError(f"container trailing bytes: {len(data)-off}")
    print(f"Extracted {len(entries)} files to {out}")

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("source",type=Path); ap.add_argument("out",type=Path)
    a=ap.parse_args(); extract(a.source,a.out)
if __name__=="__main__": main()
