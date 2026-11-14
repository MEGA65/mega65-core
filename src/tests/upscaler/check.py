#!/usr/bin/env python3
"""check.py <tb_upscaler's output> [pal|ntsc] [first frame to check] [narrow]

Checks what tb_upscaler wrote: that the upscaler's output is 720p as
CTA-861 has it (but for the line's length, which follows the input), that it
stays locked to the input, and that the picture is the input's, whole and in
order. Exits 0 if so.
"""
import sys, collections

name = sys.argv[1]
std = sys.argv[2] if len(sys.argv) > 2 else 'pal'
first = int(sys.argv[3]) if len(sys.argv) > 3 else 2
HS_ON = 1720 if std == 'pal' else 1390
narrow = len(sys.argv) > 4 and sys.argv[4] == 'narrow'
WIDTH = 924 if std == 'pal' else 912
if narrow:
    WIDTH = 688 if std == 'pal' else 680
NOMINAL = 1980 if std == 'pal' else 1650

L = collections.defaultdict(list); V = {}; F = {}; P = []; I = []
for ln in open(name):
    t = ln.split()
    v = list(map(int, t[1:]))
    if t[0] == 'L': L[v[0]].append(v[1:])
    elif t[0] == 'V': V[v[0]] = v[1:]
    elif t[0] == 'F': F[v[0]] = v[1:]
    elif t[0] == 'P': P.append(v)
for ln in open(name + '.in'):
    I.append(list(map(int, ln.split()[1:])))

bad = []
def check(ok, what):
    if not ok and what not in bad:
        bad.append(what)

frames = [k for k in sorted(F) if k >= first]
in_frames = I[-1]
print('input: %d cycles of 27 MHz a frame, %d lines, pixels on lines %d to %d (%d)' %
      (in_frames[1], in_frames[2], in_frames[3], in_frames[4], in_frames[4] - in_frames[3] + 1))
lens = collections.Counter()
for k in frames:
    rows = L[k]
    n = len(rows)
    check(F[k][1] == n and 749 <= n <= 753, 'a frame is %d lines' % n)
    for r in rows: lens[r[1] + 1] += 1
    # every line the standard's, but the four before vsync, which are a
    # little longer or shorter
    line = collections.Counter(r[1] + 1 for r in rows).most_common(1)[0][0]
    check(line == NOMINAL, 'the line is %d clocks, not the standard\'s %d' % (line, NOMINAL))
    odd = [(r[0], r[1] + 1 - line) for r in rows if r[1] + 1 != line]
    check(all(y >= n - 4 and d != 0 and abs(d) < 300 for y, d in odd), 'lines of another length where there should be none: %s' % odd[:8])
    check(sum(r[1] + 1 for r in rows) == F[k][0], 'the lines do not add up to the frame')
    check(all(r[3] == 40 for r in rows), 'hsync is not 40 clocks')
    de = [r for r in rows if r[4]]
    check(len(de) == 720, 'data enable on %d lines' % len(de))
    check(all(r[4] == 1280 for r in de), 'data enable is not 1280 clocks')
    check([r[0] for r in de] == list(range(25, 745)), 'the lines with data enable are not 25 to 744 after vsync rose')
    # from hsync's rise to data enable: the rest of the line that began at x_count 0
    check(all(r[5] == line - HS_ON for r in de), 'data enable is not where it should be after hsync')
    check(V[k][0] == 0 and V[k][2] == 0, 'vsync does not change with hsync\'s rise: %s' % V[k])
    check(V[k][1] == 5, 'vsync is not 5 lines')
k = frames[-1]
line = collections.Counter(r[1] + 1 for r in L[k]).most_common(1)[0][0]
print('output: frames of', sorted(set(F[k][0] for k in frames)), 'clocks:', len(L[k]), 'lines of %d clocks (the standard: 750 of %d),' % (line, NOMINAL),
      'the four before vsync', [r[1] + 1 for r in L[k] if r[0] >= len(L[k]) - 4])
de = [r for r in L[k] if r[4]]
print('        hsync 40 clocks, then %s clocks to data enable (nominal 220); data enable 1280 x 720' %
      sorted(set(r[5] - 40 for r in de)))
# the frames all as long as each other; or, of whole lines only, a line apart
whole = all(r[1] + 1 == NOMINAL for k in frames for r in L[k])
spread = max(F[k][0] for k in frames) - min(F[k][0] for k in frames)
check(spread <= 4 or (whole and spread == NOMINAL), 'the frame\'s length wanders: %s' % [F[k][0] for k in frames])
if whole and spread:
    print('        frames of whole lines:', ' '.join(str(F[k][1]) for k in frames), 'lines')
# every frame shows the same line of the input on each of its lines
ref = {r[0]: (r[8], r[9]) for r in L[frames[-1]] if r[6] >= 0}
for kk in frames:
    m = {r[0]: (r[8], r[9]) for r in L[kk] if r[6] >= 0}
    check(m == ref, 'the picture is not the same from frame to frame (frame %d)' % kk)

# the picture
for k in frames:
    pic = [r for r in L[k] if r[6] >= 0]
    check(all(r[6] == (1280 - WIDTH) // 2 and r[7] == (1280 + WIDTH) // 2 - 1 for r in pic),
          'the picture is not %d wide in the middle' % WIDTH)
    ys = [r[0] - 25 for r in pic]
    check(ys == list(range(ys[0], ys[-1] + 1)), 'the picture has gaps')
    # one line of the input, or two neighbours mixed: the same all along the line
    torn = [r[0] - 25 for r in pic if r[12] != r[11] or r[14] != r[13]]
    check(not torn, 'lines differ along their length (two frames or wrong lines mixed): y %s' % torn[:10])
    # and going down by the input's lines in order
    src = []
    for r in pic:
        hi = round(r[9] / 100)
        src.append(hi * 256 + r[8])
    mixed_wrap = [i for i in range(1, len(src)) if not (0 <= src[i] - src[i-1] <= 2)]
    # (where red wraps, the mix of 255 and 0 is neither: at most one line each time)
    check(len(mixed_wrap) <= 6, 'the input\'s lines are not in order: at y %s' % [ys[i] for i in mixed_wrap[:10]])
    if k == frames[-1]:
        print('picture: output lines %d to %d (%d), pixels %d to %d; shows the input\'s lines %d to %d' %
              (ys[0], ys[-1], len(ys), pic[0][6], pic[0][7], src[0], src[-1]))
        check(abs((ys[0]) - (719 - ys[-1])) <= 2, 'the picture is not in the middle: %d above, %d below' % (ys[0], 719 - ys[-1]))
        check(src[0] - in_frames[3] in (0, 1) and src[-1] == in_frames[4], 'the picture is not the input\'s first to last line')

if P and any(p[3] or p[4] or p[5] for p in P):
    STEP = 51067 if std == 'pal' else 51739
    if narrow:
        # more than a pixel in to a pixel out: 720 over WIDTH
        STEP = 65536 + (3048 if std == 'pal' else 3855)
    pic = [p for p in P if p[3] or p[4] or p[5]]
    x0 = pic[0][2]
    worst = 0
    for p in P:
        k = p[2] - (1280 - WIDTH) // 2
        if 0 <= k < WIDTH:
            u = k * STEP
            a, f = u >> 16, (u & 0xffff) >> 10
            want = ((a % 256) * (64 - f) + (min(a + 1, 719) % 256) * f + 32) // 64
            worst = max(worst, abs(p[5] - want))
        else:
            check(p[3] == 0 and p[4] == 0 and p[5] == 0, 'the shoulders are not black')
    print('one line: pixels %d to %d; each is the input\'s pixel at %d/65536 of a pixel a step, from pixel 0 to %.2f: worst difference %d' %
          (pic[0][2], pic[-1][2], STEP, (WIDTH - 1) * STEP / 65536, worst))
    check(worst == 0, 'the line is not the input\'s 720 pixels, each where it should be')

if bad:
    print('FAILED:')
    for b in bad: print('  ', b)
    sys.exit(1)
print('ok')
