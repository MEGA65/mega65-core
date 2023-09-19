#!/usr/bin/env python3

import sys
import os
import argparse
import re
from typing import Optional

DEBUG = False

HEADER_TOP = """#ifndef %(cap_name)s_H
#define %(cap_name)s_H 1

#include "mhexes.h"

"""

SCREEN_BINH_TMPL = """mhx_screen_t %(screen)s = {
  0x%(txtram_len)04x, 0x%(colram_len)04x,
  %(cursor_x)d, %(cursor_y)d,
  0x%(txtram_start)06x,
  0x%(colram_start)06x
};

"""

SCREEN_SCRH_TMPL = """static const char %(screen)s_txtram[%(txtram_mem)d] = {
  %(txtram_hex)s
};
static const char %(screen)s_colram[%(colram_mem)d] = {
  %(colram_hex)s
};

mhx_screen_t %(screen)s = {
  0x%(txtram_len)04x, 0x%(colram_len)04x,
  %(cursor_x)d, %(cursor_y)d,
  0,
  0
};

"""

HEADER_BOT = """
#endif /* %(cap_name)s_H */
"""

def ascii2screen(c: str, default: Optional[str] = b'\x20') -> bytes:
    c = ord(c)
    if c < 0x20:
        return default
    if c < 0x40:
        return bytes([c])
    if c == 0x40:
        return b'\x00'
    if c < 0x5b:
        return bytes([c])
    if c < 0x5f:
        return bytes([c - 0x40])
    if c == 0x5f:
        return b'\x6f'
    if c == 0x5f:
        return default
    if c < 0x7b:
        return bytes([c - 0x60])
    return default

def hexify(data: str):
    res = []
    while len(data):
        res.append(', '.join(['0x%02x' % c for c in data[:16]]))
        data = data[16:]
    return ',\n  '.join(res)

NUMre = re.compile(r'^\d+$')
SIZEre = re.compile(r'^\d+x\d+$')
def parse_assignment(data: dict, line: str) -> bool:
    key, value = line.split('=', 1)
    if key not in data:
        return False
    if value.startswith('0x'):
        value = int(value, 16)
    elif value.startswith('0b'):
        value = int(value, 2)
    elif NUMre.match(value):
        value = int(value, 10)
    elif SIZEre.match(value):
        value = tuple([int(x) for x in value.split('x', 1)])
    data[key] = value
    return True

def parse_header(main: dict, line: str) -> bool:
    line = line.rstrip()
    if line == '':
        return False
    match line[0]:
        case '!':
            if main['memory_start'] is None and main['memory_end'] is None:
                main['memory_start'] = 0
            return True
        case '@':
            if not parse_assignment(main, line[1:]):
                sys.stderr.write(f"ERROR: can't parse '{line}'\n")
                sys.exit(1)
        case _:
            sys.stderr.write('ERROR: header expects @ definitions only!\n')
            sys.exit(1)
    return False

def parse_screen(screen: dict, line: str) -> bool:
    line = line.rstrip()
    if line == '':
        return False
    if line[0] != '!':
        sys.stderr.write('ERROR: text needs to be started by "!text"!\n')
    if line == '!text':
        screen['txtram'] = []
        screen['colram'] = []
        screen['_curcol'] = screen['foreground']
        return True
    if not parse_assignment(screen, line[1:]):
        sys.stderr.write(f"ERROR: can't parse '{line}'\n")
        sys.exit(1)
    return False

COLre=re.compile(r'\{(?P<col>\d*|C)\}')
def parse_text(screen: dict, line: str) -> bool:
    line = line.rstrip()
    if line == '!endtext':
        if len(screen['txtram']) > screen['size'][1]:
            sys.stderr.write(f"ERROR: screen {screen['screen']} has to many lines\n")
        while len(screen['txtram']) < screen['size'][1]:
            screen['txtram'].append(str(screen['fillchar'])[0] * screen['size'][0])
        while len(screen['colram']) < screen['size'][1]:
            screen['colram'].append(bytes([screen['_curcol']] * screen['size'][0]))
        return True
    # parse color tags first
    if DEBUG: sys.stderr.write(f"parsing {repr(line)}\n")
    tline: str = ''
    cline: bytes = b''
    while match := COLre.search(line):
        if DEBUG: sys.stderr.write(f"tline = {repr(tline)}\ncline = {cline}\nmatch = {match}\n")
        tline += line[:match.start(0)]
        cline += bytes([screen['_curcol']] * match.start(0))
        if match.group(1) == 'C':
            screen['cursor_x'] = len(tline)
            screen['cursor_y'] = len(screen['txtram'])
        else:
            screen['_curcol'] = int(match.group(1)) if match.group(1) else screen['foreground']
        line = line[match.end(0):]
    tline += line
    cline += bytes([screen['_curcol']] * len(line))
    # make line the right length
    if len(tline) > screen['size'][0]:
        sys.stderr.write(f"screen {screen['screen']} line {len(screen['txtram'])+1} to long\n")
        tline = tline[:screen['size'][0]]
    if len(cline) > screen['size'][0]:
        cline = cline[:screen['size'][0]]
    if len(tline) < screen['size'][0]:
        tline += str(screen['fillchar'])[0] * (screen['size'][0] - len(tline))
    if len(cline) < screen['size'][0]:
        cline += bytes([screen['_curcol']] * (screen['size'][0] - len(cline)))
    if DEBUG: sys.stderr.write(f"EOL\ntline = {repr(tline)}\ncline = {cline}\n")
    screen['txtram'].append(tline)
    screen['colram'].append(cline)
    return False

def add_screen(main: dict, screen: dict):
    ramsize = screen['size'][0] * screen['size'][1]
    if ramsize % main['memory_align']:
        ramsize = ((ramsize // main['memory_align']) + 1) * main['memory_align']
    screen['colram'] = b''.join(screen['colram'])
    screen['colram_len'] = len(screen['colram'])
    if len(screen['colram']) < ramsize:
        screen['colram'] += bytes([0] * (ramsize - len(screen['colram'])))
    screen['colram_mem'] = len(screen['colram'])
    screen['txtram'] = b''.join(map(ascii2screen, ''.join(screen['txtram'])))
    screen['txtram_len'] = len(screen['txtram'])
    if len(screen['txtram']) < ramsize:
        screen['txtram'] += bytes([0] * (ramsize - len(screen['txtram'])))
    screen['txtram_mem'] = len(screen['txtram'])
    screen['txtram_hex'] = hexify(screen['txtram'])
    screen['colram_hex'] = hexify(screen['colram'])
    main['screens'].append(screen)

def calc_memory(main: dict):
    total_mem = sum([scr['txtram_mem'] + scr['colram_mem'] for scr in main['screens']])
    if main['memory_start'] is None and main['memory_end'] is not None:
        main['memory_start'] = main['memory_end'] - total_mem + 1
        if main['memory_start'] < 0:
            sys.stderr.write('screen allocation does below address zero! Please raise memory_end!\n')
            sys.exit(1)
    elif main['memory_start'] is not None and main['memory_end'] is None:
        main['memory_end'] = main['memory_start'] + total_mem - 1
        if main['memory_end'] > 0x5ffff:
            sys.stderr.write('screen allocation goes above bank 5! Please lower memory_start or set memory_end instead!')
            sys.exit(1)
    sys.stdout.write('Memory allocation for screens: 0x%(memory_start)06x - 0x%(memory_end)06x\n' % main)
    addr = main['memory_start']
    for screen in main['screens']:
        screen['txtram_start'] = addr
        addr += screen['txtram_mem']
        screen['colram_start'] = addr
        addr += screen['colram_mem']
        sys.stdout.write('  screen %(screen)s: txt@%(txtram_start)06X, col@%(colram_start)06X\n' % screen)
    # write address start to file for shell expansion use
    fn = os.path.join(main['path'], main['filename'] + '.adr')
    open(fn, 'w').write('%(memory_start)X' % main)
    sys.stdout.write(f'wrote {fn}\n')

def output_bin(main: dict):
    fn = os.path.join(main['path'], main['filename'] + '.bin')
    with open(fn, 'wb') as outf:
        for screen in main['screens']:
            outf.write(screen['txtram'])
            outf.write(screen['colram'])
    sys.stdout.write(f'wrote {fn}\n')

def output_bin_header(main: dict):
    fn = os.path.join(main['path'], main['filename'] + '.h')
    with open(fn, 'wt') as outf:
        outf.write(HEADER_TOP % main)
        for screen in main['screens']:
            outf.write(SCREEN_BINH_TMPL % screen)
        outf.write('#define %(cap_name)s_INIT ;\n' % main)
        outf.write(HEADER_BOT % main)
    sys.stdout.write(f'wrote {fn}\n')

def output_scr_header(main: dict):
    fn = os.path.join(main['path'], main['filename'] + '_scr.h')
    with open(fn, 'wt') as outf:
        outf.write(HEADER_TOP % main)
        for screen in main['screens']:
            outf.write(SCREEN_SCRH_TMPL % screen)
        outf.write('#define %(cap_name)s_INIT %(name)s_init()\n\nvoid %(name)s_init(void)\n{\n' % main)
        for screen in main['screens']:
            outf.write('  %(screen)s.screen_start = (long)&%(screen)s_txtram;\n  %(screen)s.color_start = (long)&%(screen)s_colram;\n' % screen)
        outf.write('}\n')
        outf.write(HEADER_BOT % main)
    sys.stdout.write(f'wrote {fn}\n')

def main():
    parser = argparse.ArgumentParser(description="MEGA65 Screen Builder")
    parser.add_argument('--verbose', action="store_true", help="verbose output")
    parser.add_argument('scrdef', nargs=1, metavar="SCRDEF", help="screen definition file")
    args = parser.parse_args()
    
    args.scrdef = args.scrdef[0]
    path, filename = os.path.split(args.scrdef)

    main = {
        'memory_start': None,
        'memory_end': None,
        'memory_align': 1,
        'path': path,
        'filename': filename.replace(".scr", "-screens"),
        'name': filename.replace(".scr", "-screens").replace('-', '_'),
        'cap_name': filename.replace(".scr", "-screens").replace('-', '_').upper(),
        'screens': [],
    }
    SCREEN_TEMPLATE = {
        'screen': None,
        'size': (1, 1),
        'cursor_x': -1,
        'cursor_y': -1,
        'background': 0,
        'foreground': 1,
        'fillchar': ' '
    }
    screen = {x: y for x, y in SCREEN_TEMPLATE.items()}

    state = 1
    with open(args.scrdef, 'r', encoding="UTF-8") as srcdef:
        for line in srcdef:
            if state == 1:
                if parse_header(main, line):
                    if main['memory_start'] is None and main['memory_end'] is None:
                        sys.stdout.write('note: setting memory_end to 0x5ffff\n')
                    state = 2
            if state == 2:
                if parse_screen(screen, line):
                    state = 3
            elif state == 3:
                if parse_text(screen, line):
                    sys.stdout.write('adding screen %(screen)s\n' % screen)
                    add_screen(main, screen)
                    screen = {x: y for x, y in SCREEN_TEMPLATE.items()}
                    state = 2
    calc_memory(main)
    output_bin(main)
    output_bin_header(main)
    output_scr_header(main)

if __name__ == "__main__":
    main()
