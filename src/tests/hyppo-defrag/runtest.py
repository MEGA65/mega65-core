# runtest.py img name action [x [name2]]
# Runs, in hyppotest on the SD card image img, on the file name:
# dos_defrag_current (action "defrag"), dos_rmfile ("rm"), dos_attach with
# X=x ("attach"), or dos_attach with X=x then dos_rmfile on name2 ("attach+rm").
# Prints the (last) error code, the sectors read and written and, for attach,
# the drive's start sector (DxSTARTSEC).
import sys,subprocess,os
root=os.path.abspath(os.path.join(os.path.dirname(__file__),'..','..','..'))
img,name,action=sys.argv[1],sys.argv[2],sys.argv[3]
name2=sys.argv[5] if len(sys.argv)>5 else name
x=int((sys.argv[4] if len(sys.argv)>4 else '$00').replace('$','0x'),0)
def setname(n):
  return 'poke dos_requested_filename '+' '.join('$%02x'%b for b in n.encode()+b'\0')+f'\npoke dos_requested_filename_len ${len(n):02x}\n'
t=f'''test "{action} {name}"
loadhyppo {root}/bin/HICKUP.M65
loadhypposymbols {root}/src/hyppo/HICKUP.sym
jsr dos_clearall
jsr dos_read_partitiontable
let x = $00
jsr dos_cdroot
poke disable_lfn_byte $2c
'''+setname(name)
if action=='defrag':
  t+='jsr dos_findfile\njsr dos_closefile\njsr dos_defrag_current\npeek dos_error_code\n'
elif action=='rm':
  t+='jsr dos_findfile\njsr dos_closefile\njsr dos_rmfile\npeek dos_error_code\n'
elif action=='attach+rm':
  t+=f'let x = ${x:02x}\njsr dos_attach\n'+setname(name2)+'jsr dos_findfile\njsr dos_closefile\njsr dos_rmfile\npeek dos_error_code\n'
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
