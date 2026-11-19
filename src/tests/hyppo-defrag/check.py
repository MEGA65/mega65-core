# check.py img datadir [name11 ...]
# Prints, per file: start cluster, runs of clusters, content against
# datadir; FAT1 == FAT2; fsck.vfat; and for name11, the start sector.
import sys,subprocess,os
from fatimg import Img,runs,BASE
img,dd=sys.argv[1],sys.argv[2]; im=Img(img)
ref={'GAME    D81':'GAME.D81','MEINLA~1D81':'LONG.D81','B       BIN':'B.BIN','C       BIN':'C.BIN'}
for n,cl,ln in im.entries():
  ch=im.chain(cl); data=b''.join(im.rd(c) for c in ch)[:ln]
  good=data==open(os.path.join(dd,ref[n]),'rb').read()
  print(f'{n} start={cl} sector=${im.data//512+(cl-2)*im.spc:08x} fragments={len(runs(ch))} content={"ok" if good else "BAD"}')
print('FAT1==FAT2:',im.fats[0]==im.fats[1])
part=img+'.part'
with open(img,'rb') as f, open(part,'wb') as g: f.seek(BASE); g.write(f.read())
r=subprocess.run(['fsck.vfat','-n',part],capture_output=True,text=True)
bad=[l for l in r.stdout.splitlines() if not any(k in l for k in ('Warning: Filesystem is FAT32','but has only','may lead to problems','fsck.fat','Free cluster summary','files,','Leaving filesystem'))]
print('fsck:', 'clean' if not bad else 'PROBLEMS '+'; '.join(bad))
os.remove(part)
