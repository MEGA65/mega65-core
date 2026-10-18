#!/usr/bin/env python3
"""Fetch physical MEGA65 memory through its UART monitor (requires pyserial)."""

import argparse
import hashlib
from pathlib import Path
import re
import sys
import time


class Monitor:
    def __init__(self, port, timeout=3, log=None):
        self.port = port
        self.timeout = timeout
        self.log = log

    def command(self, command):
        self.port.write((command + '\r').encode('ascii'))
        reply = bytearray()
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            reply.extend(self.port.read(4096))
            if reply.endswith(b'\r\n.'):
                if self.log:
                    self.log.write(command + '\n' + reply.decode('ascii', errors='replace') + '\n')
                    self.log.flush()
                return bytes(reply)
        raise TimeoutError(f'No monitor prompt after {command!r}; received {bytes(reply[-160:])!r}')

    def sync(self):
        self.port.reset_input_buffer()
        # Cancel a partial command. A comment is safe even when trace mode is
        # active: an empty command would step the CPU.
        token = '#memfetch' + str(time.monotonic_ns())
        reply = self.command('\x15' + token)
        if token.encode() not in reply:
            raise ValueError('Monitor did not echo the synchronisation token')

    def read(self, address, length):
        """Read exactly length bytes; monitor reads are aligned to 16 bytes."""
        if length < 0 or address < 0 or address + length > 0x10000000:
            raise ValueError('Memory range must fit the 28-bit physical address space')
        result = bytearray()
        while len(result) < length:
            here = address + len(result)
            aligned = here & ~15
            skip = here - aligned
            block = 256 if length - len(result) + skip >= 256 else 16
            command = ('M' if block == 256 else 'm') + f'{aligned:x}'
            reply = self.command(command)
            rows = re.findall(rb':([0-9a-fA-F]{8}):([0-9a-fA-F]{32})', reply)
            if len(rows) != block // 16:
                raise ValueError(f'Incomplete memory reply for {command}: {reply!r}')
            for index, (location, _) in enumerate(rows):
                if int(location, 16) != aligned + index * 16:
                    raise ValueError(f'Unexpected memory address in reply for {command}')
            data = b''.join(bytes.fromhex(value.decode()) for _, value in rows)
            result.extend(data[skip:skip + length - len(result)])
        return bytes(result)


def hex_address(value):
    try:
        return int(value.removeprefix('$'), 16)
    except ValueError:
        raise argparse.ArgumentTypeError('Expected a hexadecimal address') from None


def detect_port(ports):
    ports = list(ports)
    candidates = [p for p in ports if (p.vid, p.pid) == (0x0403, 0x6010)]
    if len(candidates) == 1:
        return candidates[0].device
    if not candidates and len(ports) == 1:
        return ports[0].device
    choices = ', '.join(p.device for p in ports) or 'none'
    raise ValueError(f'Cannot select one serial port ({choices}); supply --port')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, epilog=
        'Addresses are hexadecimal; END is exclusive. Output is raw binary. '
        'No memory or SD writes are issued. Reads of I/O may have device side effects.')
    parser.add_argument('start', type=hex_address)
    parser.add_argument('end', type=hex_address)
    parser.add_argument('output', type=Path)
    parser.add_argument('--port', help='serial device; otherwise detect a single FTDI/serial port')
    parser.add_argument('--baud', type=int, default=2000000)
    parser.add_argument('--timeout', type=float, default=3, help='seconds per command (default: 3)')
    parser.add_argument('--halt', action='store_true', help='pause CPU for capture, then resume it')
    parser.add_argument('--leave-halted', action='store_true', help='pause CPU and leave it paused')
    parser.add_argument('--log', type=Path, help='save the monitor transcript, including CPU registers')
    args = parser.parse_args(argv)
    if not 0 <= args.start < args.end <= 0x10000000:
        parser.error('Require 0 <= START < END <= 10000000 (hex)')
    if args.timeout <= 0 or args.baud <= 0:
        parser.error('Timeout and baud rate must be positive')
    if args.log and args.log.resolve() == args.output.resolve():
        parser.error('Output and transcript must be different files')

    try:
        import serial
        from serial.tools import list_ports
    except ImportError:
        parser.exit(1, 'Install pyserial to use this tool: python3 -m pip install pyserial\n')

    log = None
    try:
        device = args.port or detect_port(list_ports.comports())
        # Refuse to overwrite an earlier capture or transcript.
        with args.output.open('xb') as output:
            if args.log:
                log = args.log.open('x')
            print(f'{device}: ${args.start:07X}-${args.end - 1:07X}', file=sys.stderr, flush=True)
            with serial.Serial(device, args.baud, timeout=.01,
                               write_timeout=args.timeout, exclusive=True) as port:
                monitor = Monitor(port, args.timeout, log)
                monitor.sync()
                paused = args.halt or args.leave_halted
                try:
                    if paused:
                        monitor.command('t1')
                    registers = monitor.command('r').decode('ascii', errors='replace')
                    print(registers.strip(), file=sys.stderr)
                    digest = hashlib.sha256()
                    for address in range(args.start, args.end, 4096):
                        data = monitor.read(address, min(4096, args.end - address))
                        output.write(data)
                        digest.update(data)
                        print(f'\r{output.tell()}/{args.end - args.start} bytes', end='',
                              file=sys.stderr, flush=True)
                finally:
                    if paused and not args.leave_halted:
                        monitor.command('t0')
            print(f'\nSHA256 {digest.hexdigest()}  {args.output}', file=sys.stderr)
        return 0
    except (OSError, ValueError, TimeoutError, serial.SerialException, KeyboardInterrupt) as error:
        print(f'\nCapture failed: {error}. Any output file may be incomplete.', file=sys.stderr)
        return 1
    finally:
        if log:
            log.close()


if __name__ == '__main__':
    sys.exit(main())
