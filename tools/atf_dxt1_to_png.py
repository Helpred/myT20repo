from pathlib import Path

class InStream:
    def __init__(self,data): self.data=data; self.i=0
    def read_byte(self):
        if self.i>=len(self.data):
            # original might return 0? raise helpful
            raise EOFError(f'EOF at {self.i}/{len(self.data)}')
        b=self.data[self.i]; self.i+=1; return b

class OutWindow:
    def __init__(self): self.window_size=0; self.buf=bytearray(); self.pos=0; self.out=bytearray()
    def create(self,size): self.window_size=size; self.buf=bytearray(size); self.pos=0
    def init(self,solid=False):
        if not solid: self.pos=0; self.out.clear()
    def put_byte(self,b):
        self.buf[self.pos]=b&255
        self.pos+=1
        if self.pos>=self.window_size: self.pos=0
        self.out.append(b&255)
    def get_byte(self,distance): return self.buf[(self.pos-distance-1)%self.window_size]
    def copy_block(self,distance,length):
        for _ in range(length): self.put_byte(self.get_byte(distance))

class RangeDecoder:
    def __init__(self): self.stream=None; self.code=0; self.range=0xffffffff
    def set_stream(self,s): self.stream=s
    def init(self):
        self.code=0; self.range=0xffffffff
        for _ in range(5): self.code=((self.code<<8)|self.stream.read_byte()) & 0xffffffff
    def norm(self):
        if (self.range & 0xff000000)==0:
            self.code=((self.code<<8)|self.stream.read_byte()) & 0xffffffff
            self.range=(self.range<<8)&0xffffffff
    def decode_direct_bits(self,n):
        result=0
        for _ in range(n):
            self.range >>=1
            # standard unsigned range decoder
            if self.code >= self.range:
                self.code -= self.range
                bit=1
            else:
                bit=0
            result=(result<<1)|bit
            if (self.range & 0xff000000)==0:
                self.code=((self.code<<8)|self.stream.read_byte()) & 0xffffffff
                self.range=(self.range<<8)&0xffffffff
        return result
    def decode_bit(self,probs,index):
        prob=probs[index]
        new_bound=(self.range>>11)*prob
        if self.code < new_bound:
            self.range=new_bound
            probs[index]=prob+((2048-prob)>>5)
            bit=0
        else:
            self.range=(self.range-new_bound)&0xffffffff
            self.code=(self.code-new_bound)&0xffffffff
            probs[index]=prob-(prob>>5)
            bit=1
        if (self.range & 0xff000000)==0:
            self.code=((self.code<<8)|self.stream.read_byte()) & 0xffffffff
            self.range=(self.range<<8)&0xffffffff
        return bit

def init_probs(n): return [1024]*n

class BitTree:
    def __init__(self,bits): self.bits=bits; self.models=init_probs(1<<bits)
    def init(self): self.models[:]=[1024]*len(self.models)
    def decode(self,rd):
        m=1
        for _ in range(self.bits): m=(m<<1)|rd.decode_bit(self.models,m)
        return m-(1<<self.bits)
    def reverse_decode(self,rd):
        m=1; sym=0
        for i in range(self.bits):
            bit=rd.decode_bit(self.models,m); m=(m<<1)|bit; sym |= bit<<i
        return sym

def reverse_decode2(models,start,rd,bits):
    m=1; sym=0
    for i in range(bits):
        bit=rd.decode_bit(models,start+m); m=(m<<1)|bit; sym |= bit<<i
    return sym

class LenDecoder:
    def __init__(self):
        self.choice=init_probs(2); self.low=[]; self.mid=[]; self.high=BitTree(8); self.n=0
    def create(self,n):
        while self.n<n:
            self.low.append(BitTree(3)); self.mid.append(BitTree(3)); self.n+=1
    def init(self):
        self.choice[:]=[1024,1024]
        for x in self.low: x.init()
        for x in self.mid: x.init()
        self.high.init()
    def decode(self,rd,pos_state):
        if rd.decode_bit(self.choice,0)==0: return self.low[pos_state].decode(rd)
        if rd.decode_bit(self.choice,1)==0: return 8+self.mid[pos_state].decode(rd)
        return 16+self.high.decode(rd)

class Decoder2:
    def __init__(self): self.decoders=init_probs(0x300)
    def init(self): self.decoders[:]=[1024]*len(self.decoders)
    def decode_normal(self,rd):
        sym=1
        while sym<0x100: sym=(sym<<1)|rd.decode_bit(self.decoders,sym)
        return sym&255
    def decode_with_match_byte(self,rd,match):
        sym=1
        while sym<0x100:
            matchbit=(match>>7)&1; match=(match<<1)&255
            bit=rd.decode_bit(self.decoders,((1+matchbit)<<8)+sym)
            sym=(sym<<1)|bit
            if matchbit != bit:
                while sym<0x100: sym=(sym<<1)|rd.decode_bit(self.decoders,sym)
                break
        return sym&255

class LiteralDecoder:
    def __init__(self): self.coders=[]; self.num_prev=0; self.num_pos=0; self.pos_mask=0
    def create(self,num_pos_bits,num_prev_bits):
        if self.coders and self.num_prev==num_prev_bits and self.num_pos==num_pos_bits: return
        self.num_pos=num_pos_bits; self.pos_mask=(1<<num_pos_bits)-1; self.num_prev=num_prev_bits
        self.coders=[Decoder2() for _ in range(1<<(self.num_prev+self.num_pos))]
    def init(self):
        for c in self.coders: c.init()
    def get_decoder(self,pos,prev):
        return self.coders[((pos&self.pos_mask)<<self.num_prev)+((prev&255)>>(8-self.num_prev))]

class Decoder:
    def __init__(self):
        self.out=OutWindow(); self.rd=RangeDecoder()
        self.is_match=init_probs(192); self.is_rep=init_probs(12); self.is_rep_g0=init_probs(12); self.is_rep_g1=init_probs(12); self.is_rep_g2=init_probs(12); self.is_rep0_long=init_probs(192)
        self.pos_slot=[BitTree(6) for _ in range(4)]; self.pos_dec=init_probs(114); self.pos_align=BitTree(4)
        self.len_dec=LenDecoder(); self.rep_len_dec=LenDecoder(); self.literal=LiteralDecoder(); self.dict_size=-1; self.dict_check=-1
    def set_dict(self,n):
        if n<0:return False
        self.dict_size=n; self.dict_check=max(n,1); self.out.create(max(self.dict_check,4096)); return True
    def set_lclppb(self,lc,lp,pb):
        if lc>8 or lp>4 or pb>4:return False
        n=1<<pb; self.literal.create(lp,lc); self.len_dec.create(n); self.rep_len_dec.create(n); self.pos_mask=n-1; return True
    def set_props(self,prop5):
        v=prop5[0]; lc=v%9; v//=9; lp=v%5; pb=v//5
        d=int.from_bytes(prop5[1:5],'little')
        if not self.set_lclppb(lc,lp,pb): raise ValueError('props')
        self.set_dict(d)
    def init(self):
        self.out.init(False)
        for arr in [self.is_match,self.is_rep0_long,self.is_rep,self.is_rep_g0,self.is_rep_g1,self.is_rep_g2,self.pos_dec]: arr[:]=[1024]*len(arr)
        self.literal.init()
        for p in self.pos_slot:p.init()
        self.len_dec.init(); self.rep_len_dec.init(); self.pos_align.init(); self.rd.init()
    def decode(self,data,out_size):
        self.set_props(data[:5]); ins=InStream(data[5:]); self.rd.set_stream(ins); self.init()
        state=rep0=rep1=rep2=rep3=now=prev=0
        while now<out_size:
            pos_state=now & self.pos_mask
            if self.rd.decode_bit(self.is_match,(state<<4)+pos_state)==0:
                d2=self.literal.get_decoder(now,prev); now+=1
                prev=d2.decode_with_match_byte(self.rd,self.out.get_byte(rep0)) if state>=7 else d2.decode_normal(self.rd)
                self.out.put_byte(prev)
                state=0 if state<4 else state-(3 if state<10 else 6)
            else:
                if self.rd.decode_bit(self.is_rep,state)==1:
                    length=0
                    if self.rd.decode_bit(self.is_rep_g0,state)==0:
                        if self.rd.decode_bit(self.is_rep0_long,(state<<4)+pos_state)==0:
                            state=9 if state<7 else 11; length=1
                    else:
                        if self.rd.decode_bit(self.is_rep_g1,state)==0: distance=rep1
                        else:
                            if self.rd.decode_bit(self.is_rep_g2,state)==0: distance=rep2
                            else: distance=rep3; rep3=rep2
                            rep2=rep1
                        rep1=rep0; rep0=distance
                    if length==0:
                        length=2+self.rep_len_dec.decode(self.rd,pos_state); state=8 if state<7 else 11
                else:
                    rep3=rep2; rep2=rep1; rep1=rep0
                    length=2+self.len_dec.decode(self.rd,pos_state); state=7 if state<7 else 10
                    pos_slot=self.pos_slot[length-2 if length<=5 else 3].decode(self.rd)
                    if pos_slot>=4:
                        ndb=(pos_slot>>1)-1
                        rep0=(2|(pos_slot&1))<<ndb
                        if pos_slot<14:
                            rep0 += reverse_decode2(self.pos_dec,rep0-pos_slot-1,self.rd,ndb)
                        else:
                            rep0 += self.rd.decode_direct_bits(ndb-4)<<4
                            rep0 += self.pos_align.reverse_decode(self.rd)
                            if rep0>=0x80000000: rep0-=0x100000000
                            if rep0<0:
                                if rep0==-1: break
                                raise ValueError('rep0 negative')
                    else: rep0=pos_slot
                if rep0>=now or rep0>=self.dict_check:
                    raise ValueError(f'bad distance {rep0} now {now} at input {ins.i}')
                self.out.copy_block(rep0,length); now+=length; prev=self.out.get_byte(0)
        return bytes(self.out.out[:out_size]), ins.i



import argparse, subprocess, tempfile
from PIL import Image

def read_u24be(b: bytes, off: int) -> int:
    return (b[off]<<16)|(b[off+1]<<8)|b[off+2]

def decode_atf(path: Path, out_path: Path):
    data=path.read_bytes()
    if data[:3] != b'ATF': raise ValueError('not ATF')
    # Tanki demo assets use legacy ATF header v0: ATF + 24-bit body len.
    fmt=data[6]; we=data[7]; he=data[8]; mips=data[9]
    if fmt != 2: raise ValueError(f'Only ATF compressed format 2 supported, got {fmt}')
    w=1<<we; h=1<<he
    pos=10
    blocks=[]
    for block_i in range(8):
        n=read_u24be(data,pos); pos+=3
        blocks.append(data[pos:pos+n]); pos+=n
    dxt_lzma=blocks[0]; jxr=blocks[1]
    expected=w*h//4
    indices,_=Decoder().decode(dxt_lzma,expected)
    with tempfile.TemporaryDirectory(prefix='atf_') as td:
        td=Path(td)
        jxr_p=td/'endpoints.jxr'; bmp_p=td/'endpoints.bmp'
        jxr_p.write_bytes(jxr)
        cp=subprocess.run(['JxrDecApp','-i',str(jxr_p),'-o',str(bmp_p),'-c','30'],capture_output=True,text=True)
        if cp.returncode != 0:
            raise RuntimeError(f'JxrDecApp failed: {cp.stderr or cp.stdout}')
        ep=Image.open(bmp_p).convert('RGB')
        expected_ep=(w//4,h//2)
        if ep.size != expected_ep:
            raise ValueError(f'Unexpected endpoint image {ep.size}, expected {expected_ep}')
        p=ep.load(); out=Image.new('RGB',(w,h)); o=out.load(); i=0
        bh=h//4; bw=w//4
        for by in range(bh):
            for bx in range(bw):
                c0=p[bx,by]
                c1=p[bx,by+bh]
                c2=tuple((2*a+b)//3 for a,b in zip(c0,c1))
                c3=tuple((a+2*b)//3 for a,b in zip(c0,c1))
                pal=(c0,c1,c2,c3)
                for ry in range(4):
                    bits=indices[i]; i+=1
                    yy=by*4+ry
                    for rx in range(4):
                        o[bx*4+rx,yy]=pal[(bits>>(2*rx))&3]
        out_path.parent.mkdir(parents=True,exist_ok=True)
        out.save(out_path,optimize=True)
    return w,h,mips

def main():
    ap=argparse.ArgumentParser(description='Decode Tanki 2.0 Demo ATF format-2 DXT1 texture to PNG')
    ap.add_argument('input',type=Path); ap.add_argument('output',type=Path)
    a=ap.parse_args(); wh=decode_atf(a.input,a.output); print(f'{a.input} -> {a.output} {wh[0]}x{wh[1]} mips={wh[2]}')
if __name__=='__main__': main()
