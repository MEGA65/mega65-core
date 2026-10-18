import dataclasses
import decimal
import pathlib
import random
import shutil
import struct
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MASK = (1 << 64) - 1


def float_bits(value):
    return struct.unpack("<Q", struct.pack("<d", value))[0]


def bits_float(value):
    return struct.unpack("<d", struct.pack("<Q", value))[0]


def canonical_float(bits):
    value = bits_float(bits)
    sign = "-" if bits >> 63 else ""
    if bits & ((1 << 63) - 1) < 1 << 52:
        return sign + "0E0"
    for precision in range(1, 18):
        text = format(abs(value), f".{precision}g")
        if float_bits(float(text)) == bits & ((1 << 63) - 1):
            parts = decimal.Decimal(text).normalize().as_tuple()
            digits = "".join(map(str, parts.digits))
            exponent = len(digits) + parts.exponent - 1
            return sign + digits[0] + ("." + digits[1:] if len(digits) > 1 else "") + "E" + str(exponent)
    raise AssertionError(bits)


def fixed_text(value, places):
    sign = "-" if value < 0 else ""
    digits = str(abs(value)).rjust(places + 1, "0")
    return sign + (digits[:-places] + "." + digits[-places:] if places else digits)


@dataclasses.dataclass
class Job:
    mode: int = 0
    text: str = ""
    value: int = 0
    kind: int = 0
    scale: int = 0
    negative: bool = False
    decimal_mark: str = "."
    style: int = 0
    decimals: int = 2
    width: int = 255
    source: int = 259
    destination: int = 16387
    capacity: int = 512
    expected_error: int = 0
    position: int = -1
    expected_value: int = 0
    expected_kind: int = 0
    expected_scale: int = 0
    expected_text: str = ""
    abort_after: int = 0
    memory_fault: bool = False


def jobs():
    result = []

    def parse(text, negative=False, decimal_mark="."):
        normal = text.replace(decimal_mark, ".")
        if "e" in normal.lower():
            value = float(normal)
            bits = float_bits(-value if negative else value)
            if bits & ((1 << 63) - 1) < 1 << 52:
                bits &= 1 << 63
            result.append(Job(text=text, negative=negative, decimal_mark=decimal_mark,
                              expected_value=bits, expected_kind=1))
        else:
            places = len(normal.split(".")[1]) if "." in normal else 0
            value = int(decimal.Decimal(normal) * 10 ** places) * (-1 if negative else 1)
            result.append(Job(text=text, negative=negative, decimal_mark=decimal_mark,
                              expected_value=value & MASK, expected_scale=places))

    for value in [0, 1, -1, 127, -128, 2**31 - 1, -(2**31), 2**63 - 1, -(2**63)]:
        parse(str(value))
        result.append(Job(mode=1, value=value & MASK, expected_text=str(value)))
    for text in ["1.50", "-0.000000000000000001", ".125", "000.000", "1.", "+42"]:
        parse(text)
    for value, places in [(150, 2), (-1, 18), (0, 18), (2**63 - 1, 18), (-(2**63), 1)]:
        result.append(Job(mode=1, value=value & MASK, scale=places, expected_text=fixed_text(value, places)))
    for text in ["1E0", "-0E0", "1.25E0", "0.1E0", "1E308", "2.2250738585072014E-308",
                 "2.2250738585072011E-308", "1E-309", "-1E-99999", "1E+000003",
                 "1.7976931348623157E308", "9007199254740993E0", "9007199254740995E0",
                 "1.00000000000000011102230246251565404236316680908203125E0",
                 "1.00000000000000011102230246251565404236316680908203126E0"]:
        parse(text)
    parse("1.25E0", negative=True)
    parse("-1.25E0", negative=True)
    parse("1,50", decimal_mark=",")
    parse("1,25E0", decimal_mark=",")
    halfway = "1.00000000000000011102230246251565404236316680908203125"
    parse(halfway + "0" * 850 + "1E0")
    parse("0E" + "9" * 100)
    for bits in [0, 1 << 63, 1, (1 << 63) | 1, 1 << 52, (1 << 52) + 1,
                 0x7FEFFFFFFFFFFFFF, float_bits(0.1), float_bits(-2.5), float_bits(1e23),
                 float_bits(2**53), float_bits(1.0000000000000002), float_bits(999999999999999.9)]:
        text = canonical_float(bits)
        result.append(Job(mode=1, value=bits, kind=1, expected_text=text))
        parse(text)
    for value, kind, scale, style, places, text in [
        (float_bits(2.5), 1, 0, 4, 0, "3"), (float_bits(-2.5), 1, 0, 4, 0, "-3"),
        (125, 0, 2, 1, 1, "1.3"), (-125, 0, 2, 1, 1, "-1.3"),
        (float_bits(1.125), 1, 0, 1, 2, "1.13"), (float_bits(1.005), 1, 0, 1, 2, "1.00"),
        (3, 0, 0x82, 1, 2, "0.75"), (1, 0, 0xBE, 1, 15, "0.000000000000000"),
        (float_bits(0.125), 1, 0, 3, 1, "12.5%"),
        (float_bits(99.99), 1, 0, 2, 1, "1.0E2"),
        (float_bits(0.0), 1, 0, 2, 3, "0.000E0"),
        (float_bits(-0.0), 1, 0, 1, 2, "-0.00"),
        (12345, 0, 2, 0, 2, "123.45"), (0, 0, 0, 0, 2, "0"),
        ((1 << 63) - 1, 0, 0, 0, 2, "9223372036854775807"),
        (-(1 << 63), 0, 0, 0, 2, "-9223372036854775808"),
    ]:
        result.append(Job(mode=2, value=value & MASK, kind=kind, scale=scale, style=style,
                          decimals=places, expected_text=text))
    result.append(Job(mode=2, value=float_bits(12345.6789), kind=1, width=6, expected_text="12346"))
    result.append(Job(mode=2, value=float_bits(1e100), kind=1, width=5, expected_text="1E100"))
    result.append(Job(mode=1, value=150, scale=2, decimal_mark=",", expected_text="1,50"))
    for text, position in [("", 0), (".", 1), ("1E", 2), ("1E+", 3), ("1..2", 2),
                           ("1E+-2", 3), ("1E2E3", 3), ("1x", 1), (" 1", 0),
                           ("9223372036854775808", 19), ("-9223372036854775809", 20),
                           ("0.0000000000000000000", 21), ("1E309", 5), ("1E9999999", 9),
                           ("1.7976931348623159E308", 22)]:
        result.append(Job(text=text, expected_error=3, position=position))
    for bits in [0x7FF0000000000000, 0x7FF8000000000001]:
        result.append(Job(mode=1, value=bits, kind=1, expected_error=3))
    result.extend([Job(mode=1, value=123, capacity=2, expected_error=7),
                   Job(mode=1, value=1, scale=0x81, expected_error=3),
                   Job(mode=2, value=1, scale=19, expected_error=3),
                   Job(mode=2, value=1, scale=0xBF, expected_error=3),
                   Job(mode=2, value=0, width=0, expected_error=7),
                   Job(mode=2, value=1 << 63, kind=1, width=1, expected_error=7),
                   Job(text="123", memory_fault=True, expected_error=10),
                   Job(text="123", abort_after=5, expected_error=11),
                   Job(text="1E-300", abort_after=1000, expected_error=11),
                   Job(text="12", source=(1 << 28) - 1, expected_error=10),
                   Job(text="12", source=(1 << 28) - 2, expected_value=12),
                   Job(mode=1, value=12, destination=(1 << 28) - 2, capacity=2, expected_text="12")])
    random_source = random.Random(8173)
    for _ in range(25):
        bits = random_source.getrandbits(64)
        if (bits >> 52) & 2047 in [0, 2047]:
            continue
        text = canonical_float(bits)
        result.append(Job(mode=1, value=bits, kind=1, expected_text=text))
        parse(text)
    with decimal.localcontext() as context:
        context.prec = 1100
        for index in range(32):
            places = random_source.randrange(16)
            if index % 3 == 0:
                value = random_source.randrange(-(1 << 40), 1 << 40)
                scale = random_source.randrange(19)
                quantity = decimal.Decimal(value).scaleb(-scale)
                kind = 0
            elif index % 3 == 1:
                value = random_source.randrange(-(1 << 40), 1 << 40)
                scale = 128 + random_source.randrange(63)
                quantity = decimal.Decimal(value) / (1 << (scale - 128))
                kind = 0
            else:
                value = random_source.getrandbits(52) | (random_source.randrange(1000, 1040) << 52)
                value |= random_source.randrange(2) << 63
                quantity = decimal.Decimal.from_float(bits_float(value))
                scale, kind = 0, 1
            rounded = quantity.quantize(decimal.Decimal(1).scaleb(-places), rounding=decimal.ROUND_HALF_UP)
            result.append(Job(mode=2, value=value & MASK, kind=kind, scale=scale, style=1,
                              decimals=places, expected_text=format(rounded, "f")))
    return result


class HardwareNumberTests(unittest.TestCase):
    def test_numbers(self):
        if not shutil.which("ghdl"):
            self.skipTest("GHDL is not installed")
        vectors = jobs()
        with tempfile.TemporaryDirectory(prefix="shite-number-") as directory:
            work = pathlib.Path(directory)
            with (work / "number_jobs.txt").open("w") as stream:
                stream.write(str(len(vectors)) + "\n")
                for job in vectors:
                    raw, expected = job.text.encode("ascii"), job.expected_text.encode("ascii")
                    stream.write(f"{job.mode} {int(job.negative)} {job.kind} {job.scale} {ord(job.decimal_mark)} "
                                 f"{job.style} {job.decimals} {job.width} {job.source} {job.destination} "
                                 f"{job.capacity} {len(raw)} {job.value:016X} {job.expected_error} {job.position} "
                                 f"{job.expected_kind} {job.expected_scale} {job.expected_value:016X} "
                                 f"{len(expected)} {job.abort_after} {int(job.memory_fault)}\n")
                    for data in [raw, expected]:
                        stream.write(" ".join(f"{value:02X}" for value in data) + "\n")
            sources = [ROOT / "src/vhdl" / name for name in ["shite_codec_pkg.vhdl", "shite_number_pkg.vhdl",
                       "shite_number_integer.vhdl", "shite_number_text.vhdl", "tb_shite_number_text.vhdl"]]
            for command in [["ghdl", "-a", "--std=08", *map(str, sources)],
                            ["ghdl", "-e", "--std=08", "tb_shite_number_text"],
                            ["ghdl", "-r", "--std=08", "tb_shite_number_text", "--assert-level=error"]]:
                completed = subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=1200)
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn("ALL NUMBER TESTS PASSED", completed.stdout)
            print(completed.stdout.strip().splitlines()[-1])


if __name__ == "__main__":
    unittest.main()
