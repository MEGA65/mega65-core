#!/bin/bash
# Tests for HYPPO's dos_defrag_current and attach with defragmentation
# (X bit 5), in hyppotest with its SD card emulation, on FAT32 images of
# 512-byte, 4KB and 32KB clusters.  Needs bin/HICKUP.M65, src/hyppo/HICKUP.sym,
# src/tools/hyppotest and mkfs.vfat/fsck.vfat.  Exits non-zero on a failure.
T=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; cd "$W"
export PYTHONPATH="$T"
G='GAME    D81'; L='MEINLA~1D81'
fails=0
expect() { # description, command output, regex
  if grep -qE -- "$3" <<<"$2"; then echo "PASS  $1"; else echo "FAIL  $1"; sed 's/^/      /' <<<"$2"; fails=$((fails+1)); fi
}
fragments() { python3 -c "import fatimg;im=fatimg.Img('$1');print(len(fatimg.runs(im.chain([c for n,c,l in im.entries() if n=='$2'][0]))))"; }
clusters() { python3 -c "import fatimg;print(fatimg.clusters('$1'))"; }
nclusters() { python3 -c "import fatimg;im=fatimg.Img('$1');print(len(im.chain([c for n,c,l in im.entries() if n=='$2'][0])))"; }
for spc in 1 8 64; do
  python3 "$T/addfiles.py" t.img $spc; CC=$(clusters t.img); n=$(nclusters t.img "$G")
  python3 "$T/frag.py" t.img "$G" $((n/4)) $((n/8)) $((CC*6/10))
  python3 "$T/frag.py" t.img "$G" $((n/2)) $((n/8)) $((CC*7/10))
  python3 "$T/frag.py" t.img "$L" $((n/3)) $((n/8)) $((CC*8/10))
  cp t.img base.img
  expect "spc=$spc: GAME.D81 fragmented" "$(fragments t.img "$G")" '^5$'
  expect "spc=$spc: attach without bit 5 fails, no writes" "$(python3 "$T/runtest.py" t.img GAME.D81 attach '$00')" 'sim=ok err=\$8B .*writes=0 '
  expect "spc=$spc: image unchanged" "$(cmp t.img base.img && echo same)" same
  expect "spc=$spc: defrag GAME.D81" "$(python3 "$T/runtest.py" t.img GAME.D81 defrag)" 'sim=ok err=\$00'
  out=$(python3 "$T/check.py" t.img data)
  expect "spc=$spc: GAME.D81 contiguous, content intact" "$out" "^$G .*fragments=1 content=ok"
  expect "spc=$spc: other files intact" "$(grep -c 'content=ok' <<<"$out")" '^4$'
  expect "spc=$spc: FAT1 == FAT2" "$out" 'FAT1==FAT2: True'
  expect "spc=$spc: fsck clean" "$out" 'fsck: clean'
  expect "spc=$spc: second defrag writes nothing" "$(python3 "$T/runtest.py" t.img GAME.D81 defrag)" 'err=\$00 .*writes=0$'
  r=$(python3 "$T/runtest.py" t.img 'Mein langes Spiel.d81' attach '$21')
  expect "spc=$spc: attach long name, drive 1, bit 5" "$r" 'sim=ok err=\$00'
  out=$(python3 "$T/check.py" t.img data)
  sec=$(grep "^$L" <<<"$out" | sed "s/.*sector=.\([0-9a-f]*\).*/\1/")
  expect "spc=$spc: D690 = start sector $sec" "$r" "startsec=.$sec"
  expect "spc=$spc: long name file contiguous, content intact" "$out" "^$L .*fragments=1 content=ok"
  expect "spc=$spc: fsck clean after attach" "$out" 'fsck: clean'
done
python3 "$T/addfiles.py" t.img 8; CC=$(clusters t.img); python3 "$T/frag.py" t.img "$G" 50 25 $((CC*6/10))
python3 -c "
import fatimg; im=fatimg.Img('t.img')
for c in range(2, fatimg.clusters('t.img')+2):
  if im.get(c)==0: im.set(c,0x0ffffff7)
im.flush()"
cp t.img base.img
expect "card full: error \$8C, no writes" "$(python3 "$T/runtest.py" t.img GAME.D81 defrag)" 'err=\$8C .*writes=0$'
expect "card full: image unchanged" "$(cmp t.img base.img && echo same)" same
python3 "$T/addfiles.py" t.img 8; CC=$(clusters t.img); python3 "$T/frag.py" t.img "$G" 50 25 $((CC*6/10))
python3 -c "
import fatimg; im=fatimg.Img('t.img')
ch=im.chain([c for n,c,l in im.entries() if n=='$G'][0])
im.set(ch[150],0x0fffffff)
for c in ch[151:]: im.set(c,0)
im.flush()"
cp t.img base.img
expect "chain shorter than length: error \$20" "$(python3 "$T/runtest.py" t.img GAME.D81 defrag)" 'sim=ok err=\$20'
expect "chain shorter than length: FATs and directory unchanged" "$(python3 -c "
import fatimg; a=fatimg.Img('t.img'); b=fatimg.Img('base.img'); print(a.fats==b.fats and a.rd(2)==b.rd(2))")" True
echo "$fails failed"
exit $((fails>0))
