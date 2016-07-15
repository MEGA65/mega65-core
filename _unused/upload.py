#!/usr/bin/env python

import pexpect;
import sys;

rom=[]
bytes_read = open(sys.argv[1], "rb").read()
load_address = ord(bytes_read[1])*256+ord(bytes_read[0])
print "load address is $"+hex(load_address)
skip=2
for b in bytes_read:
    if skip==0:
        rom.append(b.encode('hex').upper())
    else:
        skip=skip-1

p = pexpect.spawn('sudo cu -l /dev/cu.usbserial-000012FDB -s 230400',timeout=3);
#p.logfile = sys.stdout;

p.sendline('?');
p.expect('\r\n\.');

for a in xrange(0,len(rom),8):
    cmd= "\rs" + hex(a+load_address)[2:] + " " + rom[a] + " " + rom[a+1] + " " + rom[a+2] + " " + rom[a+3] + " " + rom[a+4] + " " + rom[a+5] + " " + rom[a+6] + " " + rom[a+7] + "\r"
    for c in xrange(0,len(cmd)):
        p.send(cmd[c]);
        p.expect(cmd[c]);
        
    #    for i in xrange(a,a+7):
    #    p.expect("=000"+hex(i+load_address).upper()[2:])
    p.expect(".*\r\n\.");
    print hex(a);

print "Got here"
print p.after

