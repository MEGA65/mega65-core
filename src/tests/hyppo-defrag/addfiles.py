# addfiles.py img spc [start] : builds a 64MB SD card image, one FAT32
# partition from sector start (default 2048), with test files (as mtools would)
import sys,struct,subprocess,os,random
import fatimg
from fatimg import Img
img,spc=sys.argv[1],int(sys.argv[2])
start=int(sys.argv[3]) if len(sys.argv)>3 else 2048
f=open(img,'wb'); f.truncate(64<<20)
mbr=bytearray(512); mbr[446:462]=bytes([0,0,0,0,0x0c,0,0,0])+struct.pack('<II',start,64*2048-start); mbr[510:]=b'\x55\xaa'
f.write(mbr); f.close()
subprocess.run(['mkfs.vfat','-F','32','-s',str(spc),'-n','MEGA65','--offset',str(start),img,str((64*2048-start)//2)],check=True,capture_output=True)
im=Img(img)
def lfn_entries(long,short11):
  ck=0
  for c in short11: ck=(((ck&1)<<7)+(ck>>1)+c)&0xff
  u=long.encode('utf-16le')+b'\0\0'
  while len(u)%26: u+=b'\xff\xff'
  parts=[u[i:i+26] for i in range(0,len(u),26)]; out=[]
  for n,p in enumerate(parts,1):
    e=bytearray(32); e[0]=n|(0x40 if n==len(parts) else 0)
    e[1:11]=p[0:10]; e[11]=0x0f; e[13]=ck; e[14:26]=p[10:22]; e[28:32]=p[22:26]
    out.append(bytes(e))
  return out[::-1]
nxt=3; ents=[]
def add(short11,data,long=None):
  global nxt
  n=(len(data)+im.cs-1)//im.cs; first=nxt
  for i in range(n):
    im.wr(nxt,data[i*im.cs:(i+1)*im.cs].ljust(im.cs,b'\0'))
    im.set(nxt,nxt+1 if i<n-1 else 0x0fffffff); nxt+=1
  if long: ents.extend(lfn_entries(long,short11))
  e=bytearray(32); e[0:11]=short11; e[11]=0x20
  struct.pack_into('<HI',e,26,first&0xffff,len(data)); struct.pack_into('<H',e,20,first>>16)
  ents.append(bytes(e))
random.seed(1)
os.makedirs('data',exist_ok=True)
files={}
for nm in ['B.BIN','GAME.D81','LONG.D81','C.BIN']:
  files[nm]=random.randbytes(819200 if nm.endswith('D81') else 40000)
  open('data/'+nm,'wb').write(files[nm])
add(b'B       BIN',files['B.BIN'])
add(b'GAME    D81',files['GAME.D81'])
add(b'MEINLA~1D81',files['LONG.D81'],'Mein langes Spiel.d81')
add(b'C       BIN',files['C.BIN'])
root=bytearray(im.rd(2)); vol=root[:32]; root=vol+b''.join(ents); im.wr(2,bytes(root).ljust(im.cs,b'\0'))
im.flush()
# FSInfo free count = unknown, so fsck's baseline is clean
fsi=struct.unpack_from('<H',open(img,'rb').read(fatimg.BASE+512)[fatimg.BASE:],48)[0]
with open(img,'r+b') as g:
  g.seek(fatimg.BASE+fsi*512+488); g.write(b'\xff\xff\xff\xff\xff\xff\xff\xff')
