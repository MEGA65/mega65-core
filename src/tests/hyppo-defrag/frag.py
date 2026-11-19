import sys
from fatimg import Img
# frag.py img NAME11 startidx count dest
im=Img(sys.argv[1]); name=sys.argv[2]; k=int(sys.argv[3]); m=int(sys.argv[4]); dest=int(sys.argv[5])
cl=[c for n,c,l in im.entries() if n==name][0]
ch=im.chain(cl)
moved=ch[k:k+m]
for i,c in enumerate(moved):
  im.wr(dest+i, im.rd(c)); im.wr(c, b'\xAA'*im.cs)  # scribble old location
  im.set(c,0)
for i in range(m-1): im.set(dest+i,dest+i+1)
im.set(ch[k-1],dest); im.set(dest+m-1, ch[k+m] if k+m<len(ch) else 0x0fffffff)
im.flush()
