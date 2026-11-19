import struct,sys
BASE=2048*512
class Img:
  def __init__(s,p):
    s.f=open(p,'r+b'); s.f.seek(BASE); bs=s.f.read(512)
    s.bps,s.spc,s.res,s.nf=struct.unpack_from('<HBHB',bs,11)
    s.fatsz=struct.unpack_from('<I',bs,36)[0]; s.root=struct.unpack_from('<I',bs,44)[0]
    s.cs=s.spc*512
    s.data=BASE+(s.res+s.nf*s.fatsz)*512
    s.fats=[]
    for i in range(s.nf):
      s.f.seek(BASE+(s.res+i*s.fatsz)*512); s.fats.append(bytearray(s.f.read(s.fatsz*512)))
  def get(s,c,i=0): return struct.unpack_from('<I',s.fats[i],c*4)[0]&0x0fffffff
  def set(s,c,v):
    for fa in s.fats: struct.pack_into('<I',fa,c*4,v)
  def chain(s,c,i=0):
    out=[]
    while 2<=c<0x0ffffff0: out.append(c); c=s.get(c,i)
    return out
  def rd(s,c): s.f.seek(s.data+(c-2)*s.cs); return s.f.read(s.cs)
  def wr(s,c,d): s.f.seek(s.data+(c-2)*s.cs); s.f.write(d)
  def flush(s):
    for i,fa in enumerate(s.fats): s.f.seek(BASE+(s.res+i*s.fatsz)*512); s.f.write(fa)
    s.f.flush()
  def entries(s):
    d=b''.join(s.rd(c) for c in s.chain(s.root)); out=[]
    for i in range(0,len(d),32):
      e=d[i:i+32]
      if e[0]==0: break
      if e[11]==0x0f or e[0]==0xe5 or e[11]&8: continue
      cl=struct.unpack_from('<H',e,20)[0]<<16|struct.unpack_from('<H',e,26)[0]
      out.append((e[:11].decode(),cl,struct.unpack_from('<I',e,28)[0]))
    return out
def runs(ch):
  r=[]
  for c in ch:
    if r and c==r[-1][1]+1: r[-1][1]=c
    else: r.append([c,c])
  return r
if __name__=='__main__':
  im=Img(sys.argv[1])
  for n,cl,ln in im.entries():
    print(n,cl,ln,len(im.chain(cl)),runs(im.chain(cl)), 'FAT2 same' if im.chain(cl,1)==im.chain(cl,0) else 'FAT2 DIFFERS')
  print('FAT1==FAT2:', im.fats[0]==im.fats[1])
def clusters(p):
  im=Img(p); im.f.seek(BASE+32); tot=struct.unpack('<I',im.f.read(4))[0]
  return (tot-(im.data-BASE)//512)//im.spc
