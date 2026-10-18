"""Check UART memory decoding, bounds, and failure handling without hardware."""
import importlib.util
import contextlib
import io
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('memfetch',
    Path(__file__).resolve().parents[1] / 'src/tools/monitor_memfetch.py')
memfetch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memfetch)


class FakePort:
    def __init__(self, corrupt=None):
        self.commands = []
        self.reply = b''
        self.corrupt = corrupt

    def write(self, data):
        command = data.decode().strip('\r')
        self.commands.append(command)
        if command[0] in 'mM':
            address = int(command[1:], 16)
            length = 256 if command[0] == 'M' else 16
            rows = [(address + i, bytes((address + i + j) % 251 for j in range(16)))
                    for i in range(0, length, 16)]
            if self.corrupt == 'missing':
                rows.pop()
            if self.corrupt == 'address':
                rows[0] = (address + 16, rows[0][1])
            body = ''.join(f':{a:08X}:{v.hex()}\r\n' for a, v in rows)
        else:
            body = command + '\r\n'
        self.reply = (body + '.').encode()

    def read(self, size):
        if self.corrupt == 'timeout':
            return b''
        data, self.reply = self.reply[:19], self.reply[19:]
        return data

    def reset_input_buffer(self):
        self.reply = b''

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass


class MemoryFetchTests(unittest.TestCase):
    def test_exact_aligned_and_unaligned_ranges(self):
        for address, size in [(0x20000, 131072), (0x20003, 513), (0xfffffff, 1), (0, 0)]:
            with self.subTest(address=address, size=size):
                port = FakePort()
                monitor = memfetch.Monitor(port)
                monitor.sync()
                self.assertEqual(monitor.read(address, size),
                                 bytes(i % 251 for i in range(address, address + size)))
                self.assertTrue(all(c.startswith(('m', 'M', '\x15#')) for c in port.commands))

    def test_reject_missing_or_misaddressed_memory(self):
        for corruption in ('missing', 'address'):
            with self.subTest(corruption=corruption), self.assertRaises(ValueError):
                memfetch.Monitor(FakePort(corruption)).read(0x20000, 256)

    def test_command_timeout(self):
        with self.assertRaises(TimeoutError):
            memfetch.Monitor(FakePort('timeout'), timeout=.001).read(0, 16)

    def test_physical_address_bounds(self):
        for address, size in [(-1, 1), (0, -1), (0xfffffff, 2)]:
            with self.subTest(address=address, size=size), self.assertRaises(ValueError):
                memfetch.Monitor(FakePort()).read(address, size)

    def test_port_selection_and_ambiguity(self):
        def port(name, vid=0x0403, pid=0x6010):
            return SimpleNamespace(device=name, vid=vid, pid=pid)
        self.assertEqual(memfetch.detect_port([port('/dev/ttyUSB1')]), '/dev/ttyUSB1')
        for ports in ([], [port('a'), port('b')]):
            with self.assertRaises(ValueError):
                memfetch.detect_port(ports)

    def test_pause_cleanup_after_success_and_failed_transfer(self):
        for corruption, option in [(None, '--halt'), ('missing', '--halt'),
                                   ('missing', '--leave-halted')]:
            with self.subTest(corruption=corruption, option=option), tempfile.TemporaryDirectory() as temp:
                port = FakePort(corruption)
                serial = SimpleNamespace(Serial=lambda *a, **k: port, SerialException=OSError)
                modules = {'serial': serial, 'serial.tools': SimpleNamespace(list_ports=None)}
                output = Path(temp) / 'capture.bin'
                with patch.dict(sys.modules, modules), contextlib.redirect_stderr(io.StringIO()):
                    result = memfetch.main(['20000', '20200', str(output), '--port', 'fake', option])
                self.assertEqual(result, 1 if corruption else 0)
                self.assertIn('t1', port.commands)
                self.assertEqual('t0' in port.commands, option == '--halt')
                if not corruption:
                    self.assertEqual(len(output.read_bytes()), 512)


if __name__ == '__main__':
    unittest.main()
