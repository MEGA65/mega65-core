#!/usr/bin/env python3
"""Runs tb_sd_eth (#965) against netsd.py's own Server, playing the PC.

    sim_netsd.py WORKDIR [--flags 0|1|3] [--drop N] [--corrupt N] [-v]

WORKDIR must hold the GHDL work library with tb_sd_eth elaborated (ghdl -a /
-e there).  The harness:
  * builds a small virtual card from a scratch tree (read-only FAT32, so the
    testbench's FAT32 write must be refused; its system-partition writes go
    to the overlay);
  * takes every frame sd_eth sends from the tb_tx.fifo pipe, checks its
    Ethernet/IPv4/UDP framing and IPv4 header checksum, hands the UDP payload
    to Server.handle and sends the answers back on tb_rx.fifo as complete
    frames (with a UDP checksum, as Linux would; sd_eth ignores it);
  * before its first unicast to the MEGA65, sends an ARP request for it, as
    a kernel would, and expects sd_eth's ARP reply;
  * with --drop N / --corrupt N, loses the Nth READ response frame / flips a
    bit in it, so that the retry and bad-tag paths run;
  * afterwards checks every block the testbench logged against the card.
Exit status 0 if all is well.
"""

import argparse
import ipaddress
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import netsd  # noqa: E402
import netsd_vfat as vfat  # noqa: E402

KEY = bytes(range(0x40, 0x50))
SERVER_MAC = bytes.fromhex("020000000001")
SERVER_IP = "10.65.0.1"
SUBNET = "10.65.0.0/24"


def csum16(b):
    if len(b) % 2:
        b += b"\0"
    s = sum(struct.unpack("!%dH" % (len(b) // 2), b))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return s


def ipv4_frame(dst_mac, src_mac, src_ip, dst_ip, sport, dport, payload):
    udp_len = 8 + len(payload)
    src, dst = socket.inet_aton(src_ip), socket.inet_aton(dst_ip)
    pseudo = src + dst + struct.pack("!BBH", 0, 17, udp_len)
    udp = struct.pack("!HHHH", sport, dport, udp_len, 0) + payload
    uc = (~csum16(pseudo + udp)) & 0xFFFF or 0xFFFF
    udp = udp[:6] + struct.pack("!H", uc) + udp[8:]
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + udp_len, 0x1234, 0x4000, 64, 17, 0, src, dst)
    ip = ip[:10] + struct.pack("!H", (~csum16(ip)) & 0xFFFF) + ip[12:]
    frame = dst_mac + src_mac + b"\x08\x00" + ip + udp
    return frame + bytes(max(0, 60 - len(frame)))


def arp_request(target_ip):
    body = struct.pack("!HHBBH6s4s6s4s", 1, 0x0800, 6, 4, 1, SERVER_MAC, socket.inet_aton(SERVER_IP),
                       bytes(6), socket.inet_aton(target_ip))
    frame = b"\xff" * 6 + SERVER_MAC + b"\x08\x06" + body
    return frame + bytes(60 - len(frame))


class Harness:
    def __init__(self, args, root):
        self.args = args
        self.errors = []
        self.log = []
        self.sent = []
        a = types.SimpleNamespace(
            subnet=SUBNET, server_ip=SERVER_IP, default=None, key=None, write=False, delete=False,
            size=48, spc=1, sys_slots=4, quiet=1.0, state_dir=os.path.join(args.workdir, "state"),
            client=[netsd.ClientSpec("65=%s%s" % (root, ",key=" + KEY.hex() if args.flags else ""))])
        self.server = netsd.Server(a, self.log.append)
        self.server.send = lambda data, addr: self.sent.append((data, addr))
        self.m65_mac = None
        self.m65_ip = None
        self.arp_sent = False
        self.arp_answered = False
        self.read_frames = 0
        self.frames_in = 0
        self.served = {}              # LBA -> the sector contents served for it

    def fail(self, msg):
        self.errors.append(msg)
        print("FAIL:", msg, flush=True)

    def take(self, frame):
        """One frame from sd_eth; returns the frames to answer with"""
        self.frames_in += 1
        if len(frame) < 60:
            self.fail("short frame (%d bytes)" % len(frame))
        dst, src, etype = frame[0:6], frame[6:12], frame[12:14]
        self.m65_mac = src
        if etype == b"\x08\x06":
            htype, ptype, hl, pl, oper, sha, spa, tha, tpa = struct.unpack("!HHBBH6s4s6s4s", frame[14:42])
            ok = (dst == SERVER_MAC and oper == 2 and sha == src and tha == SERVER_MAC
                  and tpa == socket.inet_aton(SERVER_IP) and socket.inet_ntoa(spa) == self.m65_ip)
            if not ok:
                self.fail("bad ARP reply %s" % frame[:42].hex())
            self.arp_answered = True
            return []
        if etype != b"\x08\x00":
            self.fail("unknown EtherType %s" % etype.hex())
            return []
        ip = frame[14:34]
        if csum16(ip) != 0xFFFF:
            self.fail("bad IPv4 header checksum in %s" % ip.hex())
        ver, tos, tot, ident, frag, ttl, proto, _, sip, dip = struct.unpack("!BBHHHBBH4s4s", ip)
        sport, dport, ulen, ucs = struct.unpack("!HHHH", frame[34:42])
        if (ver, proto, sport, dport, ucs) != (0x45, 17, 6565, 6565, 0) or tot != 20 + ulen \
                or len(frame) != 14 + tot:
            self.fail("bad IPv4/UDP framing: %s" % frame[:42].hex())
        payload = frame[42:42 + ulen - 8]
        src_ip, dst_ip = socket.inet_ntoa(sip), socket.inet_ntoa(dip)
        hello = netsd.parse(payload) and netsd.parse(payload)[1] == netsd.OP_HELLO
        if hello and (src_ip, dst_ip, dst) != ("0.0.0.0", "255.255.255.255", b"\xff" * 6):
            self.fail("HELLO not broadcast from 0.0.0.0")
        if not hello and (dst != SERVER_MAC or dst_ip != SERVER_IP or src_ip != self.m65_ip):
            self.fail("request not addressed to us: %s %s -> %s" % (dst.hex(), src_ip, dst_ip))
        if netsd.parse(payload) and netsd.parse(payload)[0] & 0x06 != self.args.flags << 1 and not hello:
            self.fail("security flags %x, want %x" % (netsd.parse(payload)[0], self.args.flags << 1))
        self.sent = []
        self.server.handle(payload, (src_ip, sport))
        out = []
        for data, addr in self.sent:
            if addr[0] == str(ipaddress.ip_network(SUBNET).broadcast_address):
                dmac = b"\xff" * 6
                if netsd.parse(data)[1] == netsd.OP_HELLO:
                    self.m65_ip = socket.inet_ntoa(data[16:20]) if not netsd.parse(data)[0] & 0x04 \
                        else None
            else:
                dmac = self.m65_mac
                if not self.arp_sent:
                    out.append(arp_request(addr[0]))   # the kernel asks first
                    self.arp_sent = True
            f = ipv4_frame(dmac, SERVER_MAC, SERVER_IP, addr[0], 6565, addr[1], data)
            if netsd.parse(data)[1] == netsd.OP_READ:
                lba = netsd.parse(data)[4]
                card = next(iter(self.server.clients.values())).card
                self.served.setdefault(lba, set()).add(card.read_sector(lba))
                self.read_frames += 1
                if self.read_frames == self.args.drop:
                    print("(dropping read response %d)" % self.read_frames, flush=True)
                    continue
                if self.read_frames == self.args.corrupt:
                    print("(corrupting read response %d)" % self.read_frames, flush=True)
                    f = bytearray(f)
                    f[42 + 16 + 100] ^= 0x10
                    f = bytes(f)
            out.append(f)
        return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("workdir")
    ap.add_argument("--flags", type=int, default=0)
    ap.add_argument("--drop", type=int, default=0)
    ap.add_argument("--corrupt", type=int, default=0)
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--tb", default="tb_sd_eth", help="tb_sd_eth or tb_sd_eth_cache")
    args = ap.parse_args()

    os.chdir(args.workdir)
    for f in ("tb_tx.fifo", "tb_rx.fifo", "tb_reads.txt"):
        if os.path.exists(f):
            os.unlink(f)
    os.mkfifo("tb_tx.fifo")
    os.mkfifo("tb_rx.fifo")
    tmp = tempfile.mkdtemp(prefix="netsd-sim-")
    root = os.path.join(tmp, "tree")
    os.makedirs(os.path.join(root, "GAMES"))
    for i in range(30):
        with open(os.path.join(root, "GAMES", "game %02d.prg" % i), "wb") as f:
            f.write(os.urandom(3000 + 100 * i))
    with open(os.path.join(root, "MEGA65.D81"), "wb") as f:
        f.write(os.urandom(819200))

    h = Harness(args, root)
    # the system partition sector the testbench writes into
    probe = vfat.VirtualCard(root, size_mb=48, spc=1, sys_slots=4)
    sys_lba = probe.sys_start + 3000
    probe.close()

    sim = subprocess.Popen(["ghdl", "-r", "--std=08", args.tb, "-gG_FLAGS=%d" % args.flags,
                            "-gG_SYS_LBA=%d" % sys_lba, "--ieee-asserts=disable"],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out_lines = []

    def pump():
        for line in sim.stdout:
            out_lines.append(line)
            if args.verbose or "FAIL" in line or "PASS" in line or "tb_sd_eth" in line \
                    or "cache:" in line \
                    or "error" in line.lower():
                print("sim:", line.rstrip(), flush=True)
    t = threading.Thread(target=pump, daemon=True)
    t.start()

    txf = open("tb_tx.fifo", "r")
    rxf = open("tb_rx.fifo", "w")
    try:
        for line in txf:
            frame = bytes.fromhex(line.strip())
            if args.verbose:
                print("<-", frame[:60].hex(), flush=True)
            for f in h.take(frame):
                rxf.write(f.hex() + "\n")
            rxf.write(".\n")
            rxf.flush()
    except BrokenPipeError:
        pass
    rc = sim.wait()
    t.join(timeout=5)

    # check the blocks the testbench read against what was served for them
    # (a new HELLO rebuilds the card, so the card at the end can differ)
    reads = 0
    done = None
    if os.path.exists("tb_reads.txt"):
        for line in open("tb_reads.txt"):
            parts = line.split()
            if parts and parts[0] == "R":
                lba, data = int(parts[1]), bytes.fromhex(parts[2])
                reads += 1
                served = h.served.get(lba, set())
                if data not in served:
                    want = next(iter(served)) if served else bytes(512)
                    diff = [i for i in range(512) if data[i] != want[i]]
                    h.fail("sector %d read differs from what was served: %d bytes, first at %d"
                           " (%02x, want %02x)" % (lba, len(diff), diff[0], data[diff[0]], want[diff[0]]))
            elif parts and parts[0] == "DONE":
                done = int(parts[1])
    if done != 0:
        h.fail("testbench did not finish cleanly (DONE %s, exit %d)" % (done, rc))
    if not h.arp_answered:
        h.fail("no ARP reply")
    for m in h.log:
        if args.verbose:
            print("server:", m)
    print("%d frames from sd_eth, %d blocks checked, %d errors (flags %d, drop %d, corrupt %d)"
          % (h.frames_in, reads, len(h.errors), args.flags, args.drop, args.corrupt))
    shutil.rmtree(tmp)
    return 1 if h.errors else 0


if __name__ == "__main__":
    sys.exit(main())
