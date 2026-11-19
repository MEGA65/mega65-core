# runtest.py img name action [x]
# Runs dos_defrag_current (action "defrag") or dos_attach with X=x (action
# "attach") on the file name in the SD card image img, in hyppotest.
# Prints the error code, the sectors read and written and, for attach, the
# drive's start sector (DxSTARTSEC).
import sys,subprocess,os
root=os.path.abspath(os.path.join(os.path.dirname(__file__),'..','..','..'))
img,name,action=sys.argv[1],sys.argv[2],sys.argv[3]
x=int((sys.argv[4] if len(sys.argv)>4 else '$00').replace('$','0x'),0)
pk=' '.join('$%02x'%b for b in name.encode()+b'\0')
t=f'''test "{action} {name}"
loadhyppo {root}/bin/HICKUP.M65
loadhypposymbols {root}/src/hyppo/HICKUP.sym
jsr dos_clearall
jsr dos_read_partitiontable
let x = $00
jsr dos_cdroot
poke disable_lfn_byte $2c
poke dos_requested_filename {pk}
poke dos_requested_filename_len ${len(name):02x}
'''
if action=='defrag':
  t+='jsr dos_findfile\njsr dos_closefile\njsr dos_defrag_current\npeek dos_error_code\n'
else:
  s=0xd690 if x&1 else 0xd68c
  t+=f'let x = ${x:02x}\njsr dos_attach\npeek dos_error_code\n'+''.join(f'peek ${s+i:04x}\n' for i in range(4))
t+='test end\n'
open('gen.test','w').write(t)
env=dict(os.environ,HYPPOTEST_SDIMG=img,HYPPOTEST_SDLOG='1')
r=subprocess.run([root+'/src/tools/hyppotest','gen.test'],env=env,capture_output=True,text=True)
lines=r.stderr.splitlines()
peeks=[int(l.split('= $')[1][:2],16) for l in lines if l.startswith('PEEK')]
w=sum(1 for l in lines if 'WRITE' in l); rd=sum(1 for l in lines if 'read ' in l)
ok='[PASS]' in r.stdout
sec=(peeks[1]|peeks[2]<<8|peeks[3]<<16|peeks[4]<<24) if len(peeks)==5 else None
print(f'sim={"ok" if ok else "FAIL"} err=${peeks[0]:02X} reads={rd} writes={w}'+(f' startsec=${sec:08x}' if sec is not None else ''))
