#!/usr/bin/env python3
# decode.py <file from tb_hdmi> - find the data islands in a stream of TMDS
# characters, take their packets apart and check them: both error codes, and
# an InfoFrame's checksum. The error code is computed as hdl-util/hdmi does it.
import sys
from collections import Counter, defaultdict
CTRL = {0b1101010100: 0, 0b0010101011: 1, 0b0101010100: 2, 0b1010101011: 3}
T4 = [0b1010011100, 0b1001100011, 0b1011100100, 0b1011100010, 0b0101110001, 0b0100011110,
      0b0110001110, 0b0100111100, 0b1011001100, 0b0100111001, 0b0110011100, 0b1011000110,
      0b1010001110, 0b1001110001, 0b0101100011, 0b1011000011]
TERC4 = {s: i for i, s in enumerate(T4)}
GB = 0b0100110011
NAMES = {0x00: 'null', 0x01: 'clock regeneration', 0x02: 'audio samples', 0x82: 'AVI InfoFrame',
         0x83: 'SPD InfoFrame (the name)', 0x84: 'audio InfoFrame'}

def ecc(bits):
    e = 0
    for b in bits:
        e = (e >> 1) ^ (0x83 if ((e & 1) ^ b) else 0)
    return e

def tobytes(bits):
    return [sum(bits[i + k] << k for k in range(8)) for i in range(0, len(bits), 8)]

rows = []
for line in open(sys.argv[1]):
    rows.append(tuple(int(v) for v in line.split()))
print('%d characters read, frames %d to %d' % (len(rows), rows[0][1], rows[-1][1]))
# Not every character need be in the file (tb_hdmi leaves lines out): the
# stretches without a gap, numbered.
seg = [0] * len(rows)
for k in range(1, len(rows)):
    seg[k] = seg[k - 1] + (rows[k][0] != rows[k - 1][0] + 1)

islands = []; problems = []
i = 0; N = len(rows)
def cont(a, b): return rows[b][0] == rows[a][0] + (b - a)
while i < N:
    n, fr, y, x, q0, q1, q2 = rows[i]
    if CTRL.get(q1) == 1 and CTRL.get(q2) == 1:
        j = i
        while j < N and CTRL.get(rows[j][5]) == 1 and CTRL.get(rows[j][6]) == 1: j += 1
        pre = j - i
        if j + 1 < N and cont(i, j + 1) and rows[j][5] == GB and rows[j][6] == GB and rows[j+1][5] == GB and rows[j+1][6] == GB:
            lead = [TERC4.get(rows[j][4], -1), TERC4.get(rows[j+1][4], -1)]
            k = j + 2; chars = []; bad = False
            while k < N and not (rows[k][5] == GB and rows[k][6] == GB):
                d = (TERC4.get(rows[k][4]), TERC4.get(rows[k][5]), TERC4.get(rows[k][6]))
                if None in d: bad = True; break
                chars.append(d); k += 1
            if bad or k + 1 >= N or not cont(i, k + 1):
                if bad: problems.append('frame %d line %d: a character in an island that is not TERC4' % (fr, y))
                i = k + 1; continue
            m = k + 2; ctl = 0
            while m < N and all(rows[m][c] in CTRL for c in (4, 5, 6)): ctl += 1; m += 1
            islands.append(dict(fr=fr, y=y, x=x, pre=pre, lead=lead, chars=chars, ctl=ctl, seg=seg[i]))
            i = k + 2; continue
        i = j; continue
    i += 1

print('%d data islands' % len(islands))
print('  preamble lengths:', dict(Counter(il['pre'] for il in islands)))
print('  packets in an island:', dict(sorted(Counter(len(il['chars']) / 32 for il in islands).items())))
print('  leading guard band on channel 0:', dict(Counter(tuple(il['lead']) for il in islands)))
print('  control characters after an island, least:', min(il['ctl'] for il in islands))
stat = defaultdict(lambda: Counter()); spd = []; d3 = Counter(); bit3_late = 0; bit3_other = 0
sound = []; acr = Counter()
for il in islands:
    if len(il['chars']) % 32: problems.append('frame %d line %d: island of %d characters' % (il['fr'], il['y'], len(il['chars']))); continue
    for p in range(len(il['chars']) // 32):
        ch = il['chars'][32 * p:32 * p + 32]
        hb = [(c[0] >> 2) & 1 for c in ch]
        H = tobytes(hb[:24]); hecc = tobytes(hb[24:])[0]
        ok = ecc(hb[:24]) == hecc
        PB = []
        for s in range(4):
            bits = []
            for c in ch: bits += [(c[1] >> s) & 1, (c[2] >> s) & 1]
            ok = ok and ecc(bits[:56]) == tobytes(bits[56:])[0]
            PB += tobytes(bits[:56])
        t = H[0]; st = stat[t]; st['n'] += 1
        if not ok: st['bad error code'] += 1
        if t & 0x80:
            ln = H[2] & 0x1F
            if (sum(H) + sum(PB[:ln + 1])) & 0xFF: st['bad checksum'] += 1
        d3[('first packet' if p == 0 else 'later packet', ch[0][0] >> 3, min(c[0] >> 3 for c in ch[1:]))] += 1
        if p > 0 and ch[0][0] >> 3 == 0: bit3_late += 1
        if min(c[0] >> 3 for c in ch[1:]) == 0 or (p == 0 and ch[0][0] >> 3 == 1): bit3_other += 1
        if t == 0x83: spd.append((il, p, H, PB, ok))
        if t == 0x02:
            for k in range(4):
                if (H[1] >> k) & 1:
                    b = PB[7 * k:7 * k + 7]
                    sound.append((b[1] | b[2] << 8, b[4] | b[5] << 8, b[0] | b[3], il['fr'], il['y'], il['seg']))
        if t == 0x01:
            for k in range(4):
                b = PB[7 * k:7 * k + 7]
                acr[((b[1] & 15) << 16 | b[2] << 8 | b[3], (b[4] & 15) << 16 | b[5] << 8 | b[6])] += 1
        if t == 0x82 and st['n'] == 1: print('  first AVI InfoFrame:', ' '.join('%02X' % v for v in H), '|', ' '.join('%02X' % v for v in PB[:14]))
print('packets:')
for t in sorted(stat):
    st = stat[t]
    print('  %02X %-26s %6d   bad error code: %d%s' % (t, NAMES.get(t, '?'), st['n'], st['bad error code'],
          ('   bad checksum: %d' % st['bad checksum']) if t & 0x80 else ''))
# The bench's sound is a count: left goes up by 257 a sample, right by 513.
# (The first packets after reset hold what was there before the first sample.
# Across a gap in the file there is nothing to compare.)
breaks = 0; low = 0
for a, b in zip(sound[8:], sound[9:]):
    if a[5] != b[5]: continue
    if (b[0] - a[0]) & 0xFFFF != 257 or (b[1] - a[1]) & 0xFFFF != 513: breaks += 1
    if b[2]: low += 1
span = (rows[-1][0] - rows[0][0]) if len(sound) else 0
print('sound: %d samples in %d packets; samples out of sequence: %d; with the low byte not 0: %d' % (len(sound), stat[0x02]['n'], breaks, low))
print('clock regeneration (CTS, N):', dict(acr))
if breaks: problems.append('%d sound samples out of sequence' % breaks)
print('bit 3 of channel 0 (which packet, at its first character, least over the rest):', dict(d3))
print('the name packets:')
for il, p, H, PB, ok in spd:
    txt = lambda b: ''.join(chr(v) if 32 <= v < 127 else '.' for v in b)
    print('  frame %d line %d, packet %d of %d in its island: header %s, checksum byte %02X, vendor "%s", product "%s", source %02X, error codes %s'
          % (il['fr'], il['y'], p + 1, len(il['chars']) // 32, ' '.join('%02X' % v for v in H), PB[0],
             txt(PB[1:9]), txt(PB[9:25]), PB[25], 'right' if ok else 'WRONG'))
    print('    bytes:', ' '.join('%02X' % v for v in PB))
if bit3_late: problems.append('%d packets behind another in their island start with bit 3 of channel 0 low, as if an island started there' % bit3_late)
if bit3_other: problems.append('%d packets with bit 3 of channel 0 wrong elsewhere' % bit3_other)
for p in problems[:10]: print('PROBLEM:', p)
print('%d problems' % len(problems))
sys.exit(1 if problems else 0)
