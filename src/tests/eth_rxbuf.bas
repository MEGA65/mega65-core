100 rem eth.rxbuf: frames through the phy's loopback into every rx buffer, read
101 rem back by peek and by dma.  the rx buffers are block ram since #953, read
102 rem from the cpu's early fastio address; this checks that nothing broke.
103 rem no cable needed (bmcr loopback).  petcat -w65 -o eth_rxbuf.prg -- eth_rxbuf.bas
110 print "eth rx buffers":fa=0:e0=$ffde800:t0=$50000:d0=$52000:nr=0
120 nb=peek($d6e4):print "  rx buffers:";nb
130 dim h(13):for j=0 to 5:h(j)=255:next:h(6)=2:h(10)=$53:h(12)=$88:h(13)=$b5
140 rem ---- 8 kb of bytes not periodic in 256: frame g's payload is from t0+o
150 print "  making the pattern"
160 for i=0 to 8191:x=i*7+int(i/256)*29+int(i/2048)*101:poke t0+i,x-int(x/256)*256:next
170 poke $d6e0,0:sleep 1:poke $d6e0,3:sleep 1
180 ph=-1:for p=0 to 7:r=1:gosub 9000:if v<>$ffff and v<>0 and ph<0 then ph=p
190 next:if ph<0 then print "  no phy answers on mdio":end
200 p=ph:r=0:gosub 9000:b0=v:print "  phy";ph;": bmcr $";hex$(b0);"; loopback, 100 full"
210 v=$6100:gosub 9100:sleep 1:gosub 9000
220 if (v and $4000)=0 then print "  (bmcr reads $";hex$(v);": loopback did not take)"
230 poke $d6e4,$11:x=peek($d6e5):poke $d6e5,(x and $cc) or $10:poke $d6e1,0
240 rem ---- drain anything already waiting
250 if peek($d6e1) and $20 then poke $d6e1,0:poke $d6e1,2:goto 250
300 rem ---- 1. one frame at a time, through every buffer twice
310 print "  one at a time:";:e=0
320 for f=0 to 2*nb:gosub 9200:gosub 9300:if nr then 9800
330 g=f:gosub 9400:next
340 if peek($d6e1) and $20 then e=e+1:print " (a frame too many)";
350 gosub 9500
400 rem ---- 2. a burst queued, then read in order
410 k=8:if k>nb-2 then k=nb-2
420 print "  a burst of";k;":";:e=0
430 for f=100 to 99+k:gosub 9200:next
440 for g=100 to 99+k:gosub 9300:if nr then 9800
450 gosub 9400:next:gosub 9500
500 rem ---- 3. each frame read while the next is being received
510 print "  read while receiving:";:e=0
520 f=200:gosub 9200:gosub 9300:if nr then 9800
530 for f=201 to 200+2*nb:gosub 9200:g=f-1:gosub 9400:gosub 9300:if nr then 9800
540 next:g=200+2*nb:gosub 9400:gosub 9500
550 goto 9800
9000 rem ---- mdio read: v = register r of phy p
9010 poke $d6e6,r+p*32:for j=1 to 50:next:v=peek($d6e7)+256*peek($d6e8):return
9100 rem ---- mdio write: v to register r of phy p
9110 poke $d6e6,r+p*32:for j=1 to 50:next
9120 poke $d6e7,v-int(v/256)*256:poke $d6e8,int(v/256):for j=1 to 50:next:return
9150 rem ---- frame g: its length l (60-1514) and its payload's offset o
9160 x=g*331:l=1514-(x-int(x/1455)*1455):o=(g*37) and 4095:return
9200 rem ---- send frame f: broadcast, ethertype $88b5, from 02:00:00:00:53:f
9210 t=0
9220 if (peek($d6e0) and $80)=0 then t=t+1:if t<3000 then 9220
9230 g=f:gosub 9150:h(11)=f and 255
9240 for j=0 to 13:poke e0+j,h(j):next:edma 0,l-14,t0+o,e0+14
9250 poke $d6e2,l and 255:poke $d6e3,int(l/256):poke $d6e4,1:return
9300 rem ---- wait for a frame waiting (nr=1: none came)
9310 t=0
9320 if peek($d6e1) and $20 then return
9330 t=t+1:if t<3000 then 9320
9340 nr=1:return
9400 rem ---- the next frame: should be frame g.  by peek, then by dma
9410 poke $d6e1,0:poke $d6e1,2:gosub 9150:h(11)=g and 255
9420 n=peek(e0)+256*(peek(e0+1) and 7):x=peek(e0+1):c=0
9430 if n<l or n>l+4 or (x and $80) then c=1
9440 for j=0 to 13:if peek(e0+2+j)<>h(j) then c=c+1
9450 next
9460 for j=14 to l-1:if peek(e0+2+j)<>peek(t0+o+j-14) then c=c+1
9470 next
9480 edma 0,l+2,e0,d0
9490 for j=0 to 13:if peek(d0+2+j)<>h(j) then c=c+1
9491 next
9492 for j=14 to l-1:if peek(d0+2+j)<>peek(t0+o+j-14) then c=c+1
9493 next
9494 if c=0 then print ".";:return
9495 e=e+1:if e>3 then return
9496 print:print "    frame";g;": length";n;"(sent";l;"), flags $";right$(hex$(x),2);",";c;"bad";
9497 print:print "    got:";:for j=0 to 15:print " ";right$(hex$(peek(e0+2+j)),2);:next:print:return
9500 rem ---- report one check: e = number of bad frames
9510 if e=0 then print " pass":return
9520 print " fail (";e;"frames)":fa=fa+1:return
9800 rem ---- the end: the phy as it was
9810 if nr then print:print "  no frame came back: is the phy's loopback working?":fa=fa+1
9820 p=ph:r=0:v=b0:if v and $1000 then v=v or $200
9830 gosub 9100:poke $d6e1,0
9840 print:if fa then print "failed.":end
9850 print "passed."
