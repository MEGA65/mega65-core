#!/usr/bin/env python3
"""SD card over Ethernet: the PC side (MEGA65/mega65-core#965).

Serves a directory tree to MEGA65s on the LAN as a virtual SD card (see
netsd_vfat.py), over the UDP protocol in docs/sdcard-native/sd-over-ethernet.md.
Runs unprivileged: it is a plain UDP socket.

    netsd.py --subnet 192.168.1.0/24 --default ~/m65
    netsd.py --subnet 192.168.1.0/24 --client 65=~/m65-a --client 02:47:53:65:65:66=~/m65-b -w
    netsd.py dump ~/m65 card.img --size 64 --spc 1     # the virtual card as an image

Each MEGA65 is told apart by its MAC, or by the host octet it asks for, and
gets its own virtual card and session.  Without -w the FAT32 partition is
read-only (writes are refused); the system partition always takes writes, so
the freezer works, but they are kept in a scratch overlay and never reach the
host tree.  With -w the MEGA65's new and changed files and directories, and
renames, are written back to the host tree after a short quiet time; deletes
only with --delete.

Phase 1: no authentication or encryption yet.  Frames with those flag bits set
are refused.
"""

import argparse
import asyncio
import ipaddress
import os
import re
import secrets
import socket
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import netsd_vfat as vfat  # noqa: E402

PORT = 6565
MAGIC = b"MS"
VERSION = 1
HDR = struct.Struct("<2sBBIII")          # magic, ver/flags, op, session, seq, lba
F_RESPONSE, F_AUTH, F_ENCRYPT = 0x01, 0x02, 0x04

OP_HELLO, OP_READ, OP_WRITE, OP_NAK = 0x01, 0x02, 0x03, 0x7F
ST_OK, ST_RANGE, ST_READONLY, ST_IO, ST_SESSION, ST_AUTH, ST_BAD = range(7)

MAX_READ = 8
SECTOR = 512


def header(flags, op, session, seq, lba):
    return HDR.pack(MAGIC, (VERSION << 4) | flags, op, session, seq, lba)


def parse(frame):
    """(flags, op, session, seq, lba, payload) or None if not a netsd frame"""
    if len(frame) < HDR.size:
        return None
    magic, vf, op, session, seq, lba = HDR.unpack_from(frame)
    if magic != MAGIC or vf >> 4 != VERSION:
        return None
    return vf & 0x0F, op, session, seq, lba, frame[HDR.size:]


def mac_str(b):
    return ":".join("%02x" % x for x in b)


# --------------------------------------------------------------------------
# Clients
# --------------------------------------------------------------------------

class ClientSpec:
    """Which virtual card a MEGA65 gets: matched by MAC or by host octet."""

    def __init__(self, text):
        key, sep, path = text.partition("=")
        if not sep or not path:
            raise argparse.ArgumentTypeError("--client wants MAC=DIR or OCTET=DIR")
        self.mac = self.octet = None
        if re.fullmatch(r"([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}", key):
            self.mac = bytes(int(x, 16) for x in re.split("[:-]", key))
        elif key.isdigit() and 1 <= int(key) <= 254:
            self.octet = int(key)
        else:
            raise argparse.ArgumentTypeError("bad client key %r" % key)
        self.dir = os.path.expanduser(path)
        if not os.path.isdir(self.dir):
            raise argparse.ArgumentTypeError("%s is not a directory" % self.dir)


class Client:
    def __init__(self, mac, ip, card, name):
        self.mac = mac
        self.ip = ip
        self.card = card
        self.name = name
        self.session = None
        self.last_seq = None
        self.last_write = None        # (seq, response) for repeated writes
        self.last_activity = time.monotonic()
        self.last_dirty = 0.0


class Server(asyncio.DatagramProtocol):
    def __init__(self, args, log=print):
        self.args = args
        self.log = log
        self.net = ipaddress.ip_network(args.subnet, strict=False)
        self.clients = {}             # MAC -> Client
        self.by_ip = {}               # IP string -> Client
        self.transport = None
        self.server_ip = args.server_ip or guess_local_ip(self.net)
        self.stats = {"reads": 0, "writes": 0, "refused": 0}

    # ---- plumbing ------------------------------------------------------------

    def connection_made(self, transport):
        self.transport = transport
        sock = transport.get_extra_info("socket")
        if sock is not None:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    def send(self, data, addr):
        self.transport.sendto(data, addr)

    def datagram_received(self, data, addr):
        try:
            self.handle(data, addr)
        except Exception as ex:                    # never let one frame kill the server
            self.log("error handling frame from %s: %r" % (addr[0], ex))

    # ---- requests ------------------------------------------------------------

    def handle(self, data, addr):
        src_ip = addr[0]
        if src_ip != "0.0.0.0":
            try:
                if ipaddress.ip_address(src_ip) not in self.net:
                    return
            except ValueError:
                return
        p = parse(data)
        if p is None:
            return
        flags, op, session, seq, lba, payload = p
        if flags & F_RESPONSE:
            return
        if flags & (F_AUTH | F_ENCRYPT):
            self.reply_nak(addr, session, seq, lba, op, ST_AUTH)
            return
        if op == OP_HELLO:
            self.hello(addr, session, seq, payload)
            return
        client = self.by_ip.get(src_ip)
        if client is None or client.session != session:
            self.reply_nak(addr, session, seq, lba, op, ST_SESSION)
            return
        client.last_activity = time.monotonic()
        if op == OP_READ:
            self.read(client, addr, session, seq, lba, payload)
        elif op == OP_WRITE:
            self.write(client, addr, session, seq, lba, payload)
        else:
            self.reply_nak(addr, session, seq, lba, op, ST_BAD)

    def reply_nak(self, addr, session, seq, lba, op, status):
        self.stats["refused"] += 1
        if addr[0] == "0.0.0.0":
            return
        self.send(header(F_RESPONSE, OP_NAK, session, seq, lba)
                  + bytes([status, op]) + bytes(14), addr)

    def find_spec(self, mac, octet):
        for spec in self.args.client:
            if spec.mac is not None and spec.mac == mac:
                return spec
        for spec in self.args.client:
            if spec.octet is not None and spec.octet == octet:
                return spec
        return None

    def hello(self, addr, session, seq, payload):
        if len(payload) < 16:
            return
        mac, octet = payload[0:6], payload[6]
        spec = self.find_spec(mac, octet)
        if spec is not None:
            root = spec.dir
            octet = octet or spec.octet or 0
        elif self.args.default:
            root = self.args.default
        else:
            self.log("HELLO from %s (octet %d): no card for it" % (mac_str(mac), octet))
            return
        ip = self.assign_ip(mac, octet, addr[0])
        if ip is None:
            self.log("HELLO from %s: no address for it in %s" % (mac_str(mac), self.net))
            return
        client = self.clients.get(mac)
        if client is not None and client.card.root != os.path.abspath(root):
            client = None
        repeat = client is not None and client.session == session
        if not repeat and (client is None or self.can_rebuild(client)):
            if client is not None:
                self.drop(client)
            card = self.make_card(root, mac)
            client = Client(mac, ip, card, mac_str(mac))
            self.clients[mac] = client
            self.log("%s: new card from %s (%s)" % (client.name, root,
                                                    "read/write" if card.writable else "read-only"))
        if client.ip in self.by_ip and self.by_ip[client.ip] is client:
            del self.by_ip[client.ip]
        client.ip = ip
        self.by_ip[ip] = client
        if not repeat:
            client.session = session
            client.last_seq = None
            client.last_write = None
        card = client.card
        body = (socket.inet_aton(ip) + socket.inet_aton(self.server_ip)
                + struct.pack("<IBB2x", card.total, 1 if card.writable else 0, MAX_READ)
                + secrets.token_bytes(8) + mac + bytes(2))
        resp = header(F_RESPONSE, OP_HELLO, session, seq, 0) + body
        if addr[0] == "0.0.0.0":
            # The MEGA65 has no address yet: answer on the subnet broadcast
            self.send(resp, (str(self.net.broadcast_address), addr[1]))
        else:
            self.send(resp, addr)
        self.log("%s: session %08x, address %s" % (client.name, session, ip))

    def can_rebuild(self, client):
        """A new HELLO rebuilds the card from the host tree, unless the MEGA65
        wrote something that hasn't been written back yet."""
        card = client.card
        if card.dirty:
            card.reconcile()
        return not card.dirty

    def drop(self, client):
        if self.by_ip.get(client.ip) is client:
            del self.by_ip[client.ip]
        client.card.close()

    def make_card(self, root, mac):
        a = self.args
        os.makedirs(a.state_dir, exist_ok=True)
        overlay = os.path.join(a.state_dir, "overlay-%s-%d" % (mac.hex(), os.getpid()))
        return vfat.VirtualCard(root, size_mb=a.size, spc=a.spc, sys_slots=a.sys_slots,
                                writable=a.write, delete=a.delete, overlay_path=overlay,
                                log=lambda m, n=mac_str(mac): self.log("%s: %s" % (n, m)))

    def assign_ip(self, mac, octet, src_ip):
        if src_ip != "0.0.0.0":
            return src_ip                  # it already has one (and tests use this)
        if octet:
            ip = self.net.network_address + octet
            if ip in self.net and ip not in (self.net.network_address, self.net.broadcast_address):
                return str(ip)
            return None
        old = self.clients.get(mac)
        if old is not None:
            return old.ip
        taken = set(self.by_ip) | {self.server_ip}
        for h in reversed(list(self.net.hosts())):
            if str(h) not in taken:
                return str(h)
        return None

    def read(self, client, addr, session, seq, lba, payload):
        count = payload[0] if payload else 0
        if not 1 <= count <= MAX_READ:
            self.reply_nak(addr, session, seq, lba, OP_READ, ST_BAD)
            return
        card = client.card
        if lba + count > card.total:
            self.reply_nak(addr, session, seq, lba, OP_READ, ST_RANGE)
            return
        for i in range(count):
            try:
                data = card.read_sector(lba + i)
            except vfat.CardError:
                self.reply_nak(addr, session, seq, lba + i, OP_READ, ST_IO)
                return
            self.send(header(F_RESPONSE, OP_READ, session, seq, lba + i) + data, addr)
        self.stats["reads"] += count
        client.last_seq = seq

    def write(self, client, addr, session, seq, lba, payload):
        if client.last_write is not None and client.last_write[0] == seq:
            self.send(client.last_write[1], addr)        # a repeat: answer it again
            return
        if len(payload) != SECTOR:
            self.reply_nak(addr, session, seq, lba, OP_WRITE, ST_BAD)
            return
        card = client.card
        status = ST_OK
        try:
            card.write_sector(lba, payload)
        except PermissionError:
            status = ST_READONLY
        except vfat.CardError:
            status = ST_RANGE if lba >= card.total else ST_IO
        except OSError:
            status = ST_IO
        if status == ST_OK:
            self.stats["writes"] += 1
            client.last_dirty = time.monotonic()
        resp = header(F_RESPONSE, OP_WRITE, session, seq, lba) + bytes([status]) + bytes(15)
        client.last_write = (seq, resp)
        client.last_seq = seq
        self.send(resp, addr)

    # ---- background ------------------------------------------------------------

    async def housekeeping(self):
        while True:
            await asyncio.sleep(0.25)
            now = time.monotonic()
            for c in list(self.clients.values()):
                if c.card.dirty and now - c.last_dirty >= self.args.quiet:
                    c.card.reconcile()


def guess_local_ip(net):
    """Our address on net (the one the kernel would send from to a host on
    it).  connect() on a UDP socket sends nothing."""
    targets = [next(net.hosts(), net.network_address), net.broadcast_address]
    for t in targets:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                s.connect((str(t), PORT))
                return s.getsockname()[0]
        except OSError:
            continue
    return "0.0.0.0"


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] == "dump":
        ap = argparse.ArgumentParser(prog="netsd.py dump",
                                     description="Write the virtual card for DIR to an image file")
        ap.add_argument("dir")
        ap.add_argument("image")
        ap.add_argument("--size", type=int, default=4096, help="card size in MB (default 4096)")
        ap.add_argument("--spc", type=int, default=8, help="sectors per cluster (default 8)")
        ap.add_argument("--sys-slots", type=int, default=4)
        a = ap.parse_args(argv[1:])
        card = vfat.VirtualCard(a.dir, size_mb=a.size, spc=a.spc, sys_slots=a.sys_slots,
                                log=lambda m: print(m, file=sys.stderr))
        vfat.dump(card, a.image)
        card.close()
        return 0

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--subnet", required=True, help="the subnet the MEGA65s are on, e.g. 192.168.1.0/24")
    ap.add_argument("--bind", default="0.0.0.0", help="address to listen on (default all)")
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--server-ip", help="our address to tell the MEGA65s (default: worked out)")
    ap.add_argument("--client", type=ClientSpec, action="append", default=[],
                    metavar="MAC|OCTET=DIR", help="the tree for one MEGA65 (repeatable)")
    ap.add_argument("--default", metavar="DIR", help="the tree for any other MEGA65")
    ap.add_argument("-w", "--write", action="store_true", help="write the MEGA65's changes back to the trees")
    ap.add_argument("--delete", action="store_true", help="with -w, also apply deletions")
    ap.add_argument("--size", type=int, default=4096, help="virtual card size in MB (default 4096)")
    ap.add_argument("--spc", type=int, default=8, help="sectors per cluster (default 8)")
    ap.add_argument("--sys-slots", type=int, default=4, help="freeze slots in the system partition")
    ap.add_argument("--quiet", type=float, default=1.0,
                    help="seconds without writes before changes are written back (default 1)")
    ap.add_argument("--state-dir", default=os.path.join(os.path.expanduser("~"), ".cache", "netsd"),
                    help="where the write overlays live")
    a = ap.parse_args(argv)
    if not a.client and not a.default:
        ap.error("give --client and/or --default")
    if a.default:
        a.default = os.path.expanduser(a.default)
        if not os.path.isdir(a.default):
            ap.error("%s is not a directory" % a.default)
    if a.delete and not a.write:
        ap.error("--delete needs -w")

    def log(msg):
        print(time.strftime("%H:%M:%S ") + msg, flush=True)

    async def run():
        loop = asyncio.get_running_loop()
        transport, server = await loop.create_datagram_endpoint(
            lambda: Server(a, log), local_addr=(a.bind, a.port), allow_broadcast=True)
        log("serving on %s:%d for %s (our address %s)" % (a.bind, a.port, a.subnet, server.server_ip))
        if ipaddress.ip_address(server.server_ip) not in server.net:
            log("warning: %s is not on %s; give --server-ip, or the MEGA65s won't find us"
                % (server.server_ip, a.subnet))
        try:
            await server.housekeeping()
        finally:
            for c in server.clients.values():
                c.card.reconcile()
                c.card.close()
            transport.close()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
