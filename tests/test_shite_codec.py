import dataclasses
import decimal
import pathlib
import random
import shutil
import struct
import subprocess
import tempfile
import unittest
from test_shite_number_text import canonical_float


ROOT = pathlib.Path(__file__).resolve().parents[1]
NUMBER_FIXTURES = {}


def count_bytes(value):
    if value < 128:
        return bytes([value])
    return bytes([0x80 | (value & 127), value >> 7])


def integer_bytes(value):
    if -128 <= value <= 127:
        return b"\x01" + struct.pack("b", value)
    if -(1 << 31) <= value < 1 << 31:
        return b"\x02" + struct.pack("<i", value)
    return b"\x03" + struct.pack("<q", value)


@dataclasses.dataclass
class Expression:
    text: str
    code: bytes
    canonical: str
    reference: bool = False
    host_calls: int = 0


def number(text, decimal_mark="."):
    normal = text.replace(decimal_mark, ".")
    if "e" in normal.lower():
        value = float(normal)
        bits = struct.unpack("<Q", struct.pack("<d", value))[0]
        kind, scale = 1, 0
        canonical = canonical_float(bits)
        code = b"\x04" + struct.pack("<Q", bits)
    else:
        scale = len(normal.split(".")[1]) if "." in normal else 0
        value = int(decimal.Decimal(normal) * 10 ** scale)
        bits, kind = value & ((1 << 64) - 1), 0
        canonical = normal
        code = integer_bytes(value) + (bytes([6, scale]) if scale else b"")
    negative = text.startswith("-")
    lexeme = text[1:] if negative else text
    NUMBER_FIXTURES[(lexeme, negative)] = (bits, kind, scale, canonical)
    canonical_lexeme = canonical[1:] if canonical.startswith("-") else canonical
    NUMBER_FIXTURES[(canonical_lexeme.replace(".", decimal_mark), canonical.startswith("-"))] = (bits, kind, scale, canonical)
    return Expression(text, code, canonical.replace(".", decimal_mark))


def column_text(column):
    result = ""
    column += 1
    while column:
        column, remainder = divmod(column - 1, 26)
        result = chr(65 + remainder) + result
    return result


def cell(row, column, row_absolute=False, column_absolute=False, origin=(0, 0)):
    row_value = row if row_absolute else (row - origin[0]) % (1 << 20)
    column_value = column if column_absolute else (column - origin[1]) % (1 << 24)
    signed_row = row_value if row_value < 1 << 19 else row_value - (1 << 20)
    signed_column = column_value if column_value < 1 << 23 else column_value - (1 << 24)
    short = (row_value <= 32767 if row_absolute else -16384 <= signed_row <= 16383)
    short &= column_value <= 16383 if column_absolute else -8192 <= signed_column <= 8191
    if short:
        word = (1 << 31) | (int(row_absolute) << 30) | ((row_value & 32767) << 15)
        word |= (int(column_absolute) << 14) | (column_value & 16383)
        code = word.to_bytes(4, "big")
    else:
        word = (int(row_absolute) << 47) | (int(column_absolute) << 46)
        word |= row_value << 24 | column_value
        code = b"\x07" + word.to_bytes(6, "big")
    text = ("$" if column_absolute else "") + column_text(column)
    text += ("$" if row_absolute else "") + str(row + 1)
    return Expression(text, code, text, True)


def rectangle(first, last):
    text = first.text + ":" + last.text
    return Expression(text, b"\x08" + first.code + last.code, text)


def binary(left, symbol, right):
    opcode = {"+": 16, "-": 17, "*": 18, "/": 19, "^": 20, "&": 23,
              "=": 24, "<>": 25, "<": 26, "<=": 27, ">": 28, ">=": 29}[symbol]
    return Expression(f"({left.text}{symbol}{right.text})", left.code + right.code + bytes([opcode]),
                      f"({left.canonical}{symbol}{right.canonical})", host_calls=left.host_calls + right.host_calls)


def unary(child, percent=False):
    if percent:
        return Expression(f"({child.text})%", child.code + b"\x16", f"({child.canonical}%)", host_calls=child.host_calls)
    return Expression(f"-({child.text})", child.code + b"\x15", f"(-({child.canonical}))", host_calls=child.host_calls)


def call(identifier, name, arguments, separator=","):
    parts, group = [], []

    def finish_group():
        if group:
            parts.append(b"\x0d" + count_bytes(len(group)) + b"".join(group))
            group.clear()

    for argument in arguments:
        if identifier <= 6 and argument.reference:
            group.append(argument.code)
        else:
            finish_group()
            parts.append(argument.code)
    finish_group()
    code = b"".join(parts) + b"\x0c" + count_bytes(identifier) + count_bytes(len(parts))
    return Expression(name + "(" + separator.join(argument.text for argument in arguments) + ")", code,
                      name + "(" + separator.join(argument.canonical for argument in arguments) + ")",
                      host_calls=sum(argument.host_calls for argument in arguments))


def conditional(condition, first, second=None, name="IF", separator=","):
    defaulted = second is None
    second = number("0") if defaulted else second
    code = condition.code + b"\x0a" + struct.pack("<H", len(first.code) + 3)
    code += first.code + b"\x0b" + struct.pack("<H", len(second.code)) + second.code
    arguments = [condition, first] if defaulted else [condition, first, second]
    text = name + "(" + separator.join(argument.text for argument in arguments) + ")"
    canonical = name + "(" + separator.join(argument.canonical for argument in [condition, first, second]) + ")"
    return Expression(text, code, canonical, host_calls=condition.host_calls + first.host_calls + second.host_calls)


def string(text):
    spelling = '"' + text.replace('"', '""') + '"'
    raw = text.encode("ascii")
    return Expression(spelling, b"\x05" + count_bytes(len(raw)) + raw, spelling)


def host(text):
    raw = text.encode("ascii")
    return Expression(text, b"\x09" + count_bytes(len(raw)) + raw + bytes.fromhex("cfffffffffff"), text, host_calls=1)


def name_table(german=False):
    entries = [(0, "SUMME" if german else "SUM"), (0, "SUM" if german else "SUMME"),
               (1, "AVERAGE"), (2, "MIN"), (3, "MAX"), (4, "COUNT"), (7, "ABS"),
               (12, "SQRT"), (17, "WENN" if german else "IF"), (28, "PI"),
               (30, "LEN"), (33, "MID"), (39, "CONCATENATE"), (1234, "FUTURE"),
               (1300, "LONG_FUNCTION_NAME_FOR_TEST"),
               (16384, "CPU"), (32767, "EXTERNAL")]
    return b"".join(count_bytes(identifier) + name.encode("ascii") + b"\0"
                    for identifier, name in entries) + b"\0\0"


@dataclasses.dataclass
class Job:
    mode: int
    source: bytes
    expected: bytes = b""
    error: int = 0
    position: int = -1
    origin: tuple = (0, 0)
    german: bool = False
    capacity: int = 8192
    abort_after: int = 0
    memory_fault: bool = False
    host_calls: int = 0
    source_address: int = 0
    destination_address: int = 0


def jobs():
    result = []

    def expression(node, origin=(0, 0), german=False):
        result.extend([Job(0, node.text.encode("ascii"), node.code + b"\0", origin=origin, german=german, host_calls=node.host_calls),
                       Job(1, node.code + b"\0", node.canonical.encode("ascii"), origin=origin, german=german),
                       Job(0, node.canonical.encode("ascii"), node.code + b"\0", origin=origin, german=german, host_calls=node.host_calls)])

    for value in [0, 1, -1, 127, 128, -128, -129, 2147483647, 2147483648,
                  -2147483648, -2147483649, 9223372036854775807, -9223372036854775808]:
        expression(number(str(value)))
    for text in ["1.25", "1.50", "0.000000000000000001", "-123.00", "1.25E0", "-0E0", "1E-100"]:
        expression(number(text))
    for row, column in [(0, 0), (25, 25), (32767, 16383), (32768, 16384),
                        (1048575, 16777215), (0, 26), (1048575, 702)]:
        for row_lock, column_lock in [(False, False), (False, True), (True, False), (True, True)]:
            expression(cell(row, column, row_lock, column_lock))
    origin = (70000, 100000)
    for row, column in [(70001, 99999), (0, 0), (1048575, 16777215)]:
        expression(cell(row, column, origin=origin), origin)
    first, second = cell(0, 0), cell(1, 1, True, True)
    for symbol in ["+", "-", "*", "/", "^", "&", "=", "<>", "<", "<=", ">", ">="]:
        expression(binary(first, symbol, second))
    expression(unary(first))
    expression(unary(number("1")))
    expression(unary(first, percent=True))
    expression(call(28, "PI", []))
    expression(call(7, "ABS", [unary(first)]))
    expression(call(1234, "FUTURE", [first, number("7")]))
    expression(call(1300, "LONG_FUNCTION_NAME_FOR_TEST", [first, number("7")]))
    for size in [1, 2, 32, 127, 128, 129, 200]:
        expression(call(0, "SUM", [cell(index, index % 29) for index in range(size)]))
    expression(call(0, "SUM", [first, second, number("2"), first, second,
                                rectangle(first, cell(99, 2)), number("3")]))
    expression(call(0, "SUM", []))
    expression(call(0, "SUM", [cell(50000 + index, 20000 + index, True, True) for index in range(130)]))
    expression(dataclasses.replace(call(0, "SUM", [first, second]), text="summe ( (a1) , (($B$2)) )"))
    expression(dataclasses.replace(binary(first, "+", binary(second, "*", number("2"))), text="A1+$B$2*2"))
    expression(dataclasses.replace(binary(number("2"), "^", binary(number("3"), "^", number("4"))), text="2^3^4"))
    for text in ["", "abc", 'a"b', "(A1,IF())", "x" * 130]:
        expression(string(text))
    expression(call(39, "CONCATENATE", [string('a"b'), string("c")]))
    expression(conditional(first, number("1"), number("2")))
    expression(conditional(first, second))
    expression(conditional(conditional(first, second, number("0")),
                           conditional(second, first, number("3")),
                           conditional(first, number("4"), number("5"))))
    expression(binary(number("7"), "+", conditional(first, number("2"), number("3"))))
    nested = number("2")
    for unused in range(32):
        nested = conditional(first, nested, number("0"))
    expression(nested)
    for text in ["CPU(A1)", 'CPU(IF(A1,2,3),"(a)""b")', "EXTERNAL(A1,$ZZ$1048576)"]:
        expression(host(text))
    expression(conditional(first, host("CPU(A1)"), host('CPU("x")')))
    expression(host('CPU("' + "x" * 150 + '")'))
    expression(call(0, "SUMME", [number("1,50", ","), first, second], separator=";"), german=True)
    expression(conditional(first, number("1,25", ","), number("2"), name="WENN", separator=";"), german=True)
    generator = random.Random(6502)

    def random_expression(depth):
        if depth == 0 or generator.randrange(4) == 0:
            return cell(generator.randrange(100), generator.randrange(100)) if generator.randrange(2) else number(str(generator.randrange(10)))
        if generator.randrange(4) == 0:
            return conditional(random_expression(depth - 1), random_expression(depth - 1), random_expression(depth - 1))
        return binary(random_expression(depth - 1), generator.choice(["+", "-", "*", "^", "<="]), random_expression(depth - 1))

    for unused in range(30):
        expression(random_expression(3))
    result.extend([Job(0, b"1+", error=1, position=2), Job(0, b"(A1", error=1, position=0),
                   Job(0, b"MISSING(1)", error=2, position=0), Job(0, b"A0", error=4, position=0),
                   Job(0, b"ABS(1,2)", error=5), Job(0, b"IF(A1)", error=5),
                   Job(0, b'"unterminated', error=1, position=0),
                   Job(0, b"1.2.3", error=3), Job(0, b"A1+", error=1),
                   Job(0, b"A1\0+1", error=1, position=2), Job(0, b"SUM(A1,)", error=1),
                   Job(0, b"(" * 33 + b"1" + b")" * 33, error=6),
                   Job(0, b"+".join([b"1"] * 40), error=6),
                   Job(0, b"-" * 18 + b"A1", error=6),
                   Job(0, b"A1", error=7, capacity=3), Job(1, first.code + b"\0", error=7, capacity=1),
                   Job(0, b"A1", error=7, capacity=0),
                   Job(1, number("1.25E0").code + b"\0", error=7, capacity=1),
                   Job(1, b"\0", error=8), Job(1, b"\x07\0", error=8),
                   Job(1, b"\x01\x01\x01\x02\0", error=8), Job(1, b"\x01\x01\x10\0", error=8),
                   Job(1, b"\x01\0\x0a\xff\xff\0", error=8),
                   Job(1, b"\x0d\x01\0", error=8), Job(1, b"\x05\x03x", error=8),
                   Job(1, b"\x0c\0\x01\0", error=8),
                   Job(1, b"\x05\x80", error=8),
                   Job(0, b"A1+A2", error=11, abort_after=10),
                   Job(0, b"A1", error=10, memory_fault=True)])
    deep = call(1234, "FUTURE", [number("1")] * 33)
    result.append(Job(0, deep.text.encode("ascii"), error=6))
    result.append(Job(0, b"FUTURE(" + b",".join([b"CPU()"] * 256) + b")", error=7))
    nonminimal = first.code + b"\x0c\x80\0\x81\0\0"
    result.append(Job(1, nonminimal, b"SUM(A1)"))
    result.extend([Job(0, b"A1", first.code + b"\0", source_address=(1 << 28) - 2),
                   Job(0, b"A1", first.code + b"\0", destination_address=(1 << 28) - 5, capacity=5),
                   Job(0, b"A1", error=10, source_address=(1 << 28) - 1)])
    for opcode, size in [(1, 1), (2, 4), (3, 8), (4, 8), (7, 6)]:
        for truncated in range(size):
            result.append(Job(1, bytes([opcode]) + bytes(truncated), error=8))
    for row_offset in [-16385, -16384, 16383, 16384]:
        for column_offset in [-8193, -8192, 8191, 8192]:
            expression(cell(origin[0] + row_offset, origin[1] + column_offset, origin=origin), origin)
    return result


def write_bytes(stream, data):
    stream.write(" ".join(f"{value:02X}" for value in data) + "\n")


class HardwareCodecTests(unittest.TestCase):
    def test_codec(self):
        self.run_codec(False)

    def test_codec_real_numbers(self):
        self.run_codec(True)

    def run_codec(self, real_numbers):
        if not shutil.which("ghdl"):
            self.skipTest("GHDL is not installed")
        vectors = jobs()
        if real_numbers:
            vectors.extend([Job(0, b"1", error=10, memory_fault=2),
                            Job(1, b"\x01\x01\0", error=10, memory_fault=2),
                            Job(0, b"1E-20", error=11, abort_after=2000)])
        with tempfile.TemporaryDirectory(prefix="shite-codec-") as directory:
            work = pathlib.Path(directory)
            with (work / "numbers.txt").open("w") as stream:
                stream.write(str(len(NUMBER_FIXTURES)) + "\n")
                for (lexeme, negative), (bits, kind, scale, canonical) in NUMBER_FIXTURES.items():
                    raw, formatted = lexeme.encode("ascii"), canonical.encode("ascii")
                    stream.write(f"{kind} {scale} {int(negative)} {bits:016X} {len(raw)} {len(formatted)}\n")
                    write_bytes(stream, raw)
                    write_bytes(stream, formatted)
            with (work / "jobs.txt").open("w") as stream:
                stream.write(str(len(vectors)) + "\n")
                for index, job in enumerate(vectors):
                    table = name_table(job.german)
                    source_address = job.source_address or 257 + index % 8
                    destination_address = job.destination_address or 16385 + index % 8
                    stream.write(f"{job.mode} {source_address} {8192 + index % 8} {destination_address} "
                                 f"{job.capacity} {len(job.source)} {len(table)} {job.error} {job.position} "
                                 f"{len(job.expected)} {job.origin[0]} {job.origin[1]} {int(job.german)} "
                                 f"{job.abort_after} {int(job.memory_fault)} {job.host_calls}\n")
                    write_bytes(stream, job.source)
                    write_bytes(stream, table)
                    write_bytes(stream, job.expected)
            sources = [ROOT / "src/vhdl" / name for name in
                       ["shite_codec_pkg.vhdl", "shite_number_pkg.vhdl", "shite_number_integer.vhdl",
                        "shite_number_text.vhdl", "shite_formula_codec.vhdl", "tb_shite_codec.vhdl"]]
            for command in [["ghdl", "-a", "--std=08", *map(str, sources)],
                            ["ghdl", "-e", "--std=08", "tb_shite_codec"],
                            ["ghdl", "-r", "--std=08", "tb_shite_codec",
                             f"-greal_numbers={str(real_numbers).lower()}", "--assert-level=error"]]:
                completed = subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=900)
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn("ALL CODEC TESTS PASSED", completed.stdout)
            print(completed.stdout.strip())


if __name__ == "__main__":
    unittest.main()
