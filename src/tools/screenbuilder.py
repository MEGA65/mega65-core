#!/usr/bin/env python3

#
# This is used by src/utilties/megaflash/
#

import sys
import os
import argparse
import re
import struct
from typing import Optional, List

DEBUG: bool = False
ERRORS: int = 0

SCREEN_BINH_HEADER = """/*
 * Automatically generated file
 */
#ifndef %(cap_name)s_H
#define %(cap_name)s_H 1

#include "mhexes.h"

"""

SCREEN_BINH_TMPL = """extern mhx_screen_t %(mainname)s_%(screen)s;
"""

SCREEN_BINH_FOOTER = """
#endif /* %(cap_name)s_H */
"""

SCREEN_BINC_HEADER = '''/*
 * Automatically generated file
 */
#include <stdint.h>
#include "%(filename)s.h"

'''

SCREEN_BINC_DATA_TMPL = """static const char %(mainname)s_%(screen)s_txtram[%(txtram_mem)d] = {
  %(txtram_hex)s
};

%(nocol)sstatic const char %(mainname)s_%(screen)s_colram[%(colram_mem)d] = {
%(nocol)s  %(colram_hex)s
%(nocol)s};

"""

SCREEN_BINC_STRUCT_TMPL = """mhx_screen_t %(mainname)s_%(screen)s = {
  0x%(txtram_len)04x, 0x%(colram_len)04x,
  %(cursor_x)d, %(cursor_y)d,
  0x%(txtram_start_h)xL,
  0x%(colram_start_h)xL
};

"""

SCREEN_BINC_FOOTER = ''

COLORS = {
    'BLK': 0,
    'WHT': 1,
    'RED': 2,
    'CYN': 3,
    'PUR': 4,
    'GRN': 5,
    'BLU': 6,
    'YEL': 7,
    'ORG': 8,
    'ORN': 8,
    'BRN': 9,
    'LRD': 10,
    'DGY': 11,
    'MGY': 12,
    'LGR': 13,
    'LBL': 14,
    'LGY': 15,
}

MHX_FORMAT = {
    'EOS': b'\x80',
    'RON': b"\x81",
    'ROF': b"\x82",
    'CLR': b"\x83",
    'HOM': b"\x84",
    'BLK': b"\x90",
    'BLC': b"\x90",
    'WHT': b"\x91",
    'RED': b"\x92",
    'CYN': b"\x93",
    'PUR': b"\x94",
    'GRN': b"\x95",
    'BLU': b"\x96",
    'YEL': b"\x97",
    'ORG': b"\x98",
    'ORN': b"\x98",
    'BRN': b"\x99",
    'LRD': b"\x9a",
    'DGY': b"\x8b",
    'MGY': b"\x8c",
    'LGR': b"\x8d",
    'LBL': b"\x8e",
    'LGY': b"\x8f",
}
MHX_NL = b'\xca'
MHX_EOS = b'\x80'

def ascii2screen(c: str, default: Optional[str] = b'\x20') -> bytes:
    c = ord(c)
    if c == 0x0:
        return b'\x80'
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
BOOLre = re.compile(r'^(true|false)$', re.I)
def parse_assignment(data: dict, line: str) -> bool:
    key, value = line.split('=', 1)
    if key not in data:
        return False
    if key != 'size' and value.startswith('0x'):
        value = int(value, 16)
    elif value.startswith('0b'):
        value = int(value, 2)
    elif BOOLre.match(value):
        value = value.lower() == 'true'
    elif NUMre.match(value):
        value = int(value, 10)
    elif SIZEre.match(value):
        value = tuple([int(x) for x in value.split('x', 1)])
    data[key] = value
    if key == 'filename':
        data['name'] = value.replace('-', '_')
        data['cap_name'] = value.replace('-', '_').upper()
    return True

def parse_header(main: dict, line: str) -> bool:
    line = line.rstrip()
    if line == '':
        return False
    if line[0] == '!':
        if main['memory_start'] is None and main['memory_end'] is None:
            main['memory_start'] = 0
        return True
    if line[0] == '@':
        if not parse_assignment(main, line[1:]):
            sys.stderr.write(f"ERROR: can't parse '{line}'\n")
            sys.exit(1)
    else:
        sys.stderr.write('ERROR: header expects @ definitions only!\n')
        sys.exit(1)
    return False

def parse_screen(screen: dict, line: str) -> bool:
    line = line.rstrip()
    if line == '' or line[0] == '#':
        return False
    if line[0] != '!':
        sys.stderr.write('ERROR: text needs to be started by "!text"!\n')
    if line == '!text':
        screen['txtram'] = []
        screen['colram'] = []
        screen['_curcol'] = screen['foreground']
        if screen['array'] or screen['formatstring']:
            screen['fillchar'] = '\x00'
        if screen['struct'] and screen['array']:
            screen['_type'] = 'struct array'
        elif screen['array']:
            screen['_type'] = 'array'
        else:
            screen['_type'] = 'screen'
        return True
    if not parse_assignment(screen, line[1:]):
        sys.stderr.write(f"ERROR: can't parse '{line}'\n")
        sys.exit(1)
    return False

COLre=re.compile(r'\{(?P<col>\d*|C|[a-zA-Z]{3}|\*[0-9a-fA-Fx]+|![A-Z0-9_]{3,})\}')
def parse_text(screen: dict, line: str) -> bool:
    line = line.rstrip()
    if line == '!endtext':
        if screen['size'][1] == 0:
            screen['size'] = (screen['size'][0], len(screen['txtram']))
        if len(screen['txtram']) > screen['size'][1]:
            sys.stderr.write(f"ERROR: screen {screen['screen']} has to many lines\n")
        while len(screen['txtram']) < screen['size'][1]:
            screen['txtram'].append(ascii2screen(screen['fillchar'][0]) * screen['size'][0])
        while len(screen['colram']) < screen['size'][1]:
            screen['colram'].append(bytes([screen['_curcol']] * screen['size'][0]))
        if screen['array']:
            screen['cursor_x'], screen['cursor_y'] = screen['size']
            if screen['size'][1] > 40:
                sys.stderr.write(f"ERROR: screen {screen['screen']} is an array, but has width greater 40")
                sys.exit(1)
        return True
    elif line.startswith('!define '):
        parts = line.split()
        if len(parts) != 3:
            sys.stderr.write(f"ERROR: define has not correct number of arguments")
            sys.exit(1)
        screen['defines'].append(line.replace('!define', '#define'))
        return False
    elif line.startswith('!idx '):
        parts = line.split()
        if len(parts) != 2:
            sys.stderr.write(f"ERROR: define has not correct number of arguments")
            sys.exit(1)
        screen['defines'].append(f'#define {parts[1]} {len(screen["txtram"])}')
        return False
    # parse color tags first
    if DEBUG: sys.stderr.write(f"parsing {repr(line)}\n")
    tline: bytes = b''
    cline: bytes = b''
    sdata: List[int] = []
    while match := COLre.search(line):
        if DEBUG: sys.stderr.write(f"tline = {repr(tline)}\ncline = {cline}\nmatch = {match}\n")
        tline += b''.join(map(ascii2screen, line[:match.start(0)]))
        cline += bytes([screen['_curcol']] * match.start(0))
        if match.group(1) == 'C':
            screen['cursor_x'] = len(tline)
            screen['cursor_y'] = len(screen['txtram'])
        elif match.group(1).startswith('*'):
            sdata.append(int(match.group(1)[1:], 0))
        elif match.group(1).startswith('!'):
            screen['defines'].append(f"#define {match.group(1)[1:]} {len(MHX_NL.join(screen['txtram'] + [tline]))}")
        elif len(match.group(1)) == 3:
            if screen['formatstring']:
                if match.group(1) not in MHX_FORMAT:
                    sys.stderr.write(f"ERROR: undefined MHX Format character {match.group(1)}\n")
                    sys.exit(1)
                tline += MHX_FORMAT[match.group(1)]
                cline += b'\x00'
            else:
                screen['_curcol'] = COLORS.get(match.group(1), screen['foreground'])
        else:
            screen['_curcol'] = int(match.group(1)) if match.group(1) else screen['foreground']
        line = line[match.end(0):]
    tline += b''.join(map(ascii2screen, line))
    cline += bytes([screen['_curcol']] * len(line))
    # make line the right length
    if screen['size'][0] > 0 and len(tline) > screen['size'][0]:
        sys.stderr.write(f"screen {screen['screen']} line {len(screen['txtram'])+1} to long\n{repr(tline)}\n")
        tline = tline[:screen['size'][0]]
    if screen['size'][0] > 0 and len(cline) > screen['size'][0]:
        cline = cline[:screen['size'][0]]
    if screen['struct']:
        try:
            data = struct.pack(screen['struct'], *sdata)
        except struct.error as err:
            sys.stderr.write(f"ERROR: could not pack data into struct - {err}\n")
            sys.exit(1)
        tline = data + tline
        cline = b'\x00' * len(data) + cline
    if screen['size'][0] > 0 and len(tline) < screen['size'][0]:
        tline += ascii2screen(screen['fillchar'][0]) * (screen['size'][0] - len(tline))
    if screen['size'][0] > 0 and len(cline) < screen['size'][0]:
        cline += bytes([screen['_curcol']] * (screen['size'][0] - len(cline)))
    if screen['array'] and tline[-1] != ascii2screen(screen['fillchar'][0])[0]:
        sys.stderr.write(f"ERROR: array requires EOS, but line {len(screen['txtram'])+1} ends without, please make screen wider!\n")
        sys.exit(1)
    if DEBUG: sys.stderr.write(f"EOL\ntline = {repr(tline)}\ncline = {cline}\n")
    screen['txtram'].append(tline)
    screen['colram'].append(cline)
    screen['structdata'].append(sdata)
    return False

def add_screen(main: dict, screen: dict):
    if screen['formatstring']:
        screen['txtram'] = MHX_NL.join(screen['txtram']) + MHX_EOS
    else:
        screen['txtram'] = b''.join(screen['txtram'])
    screen['txtram_len'] = len(screen['txtram'])
    if screen['formatstring']:
        ramsize = len(screen['txtram'])
    else:
        ramsize = screen['size'][0] * screen['size'][1]
    if ramsize % main['memory_align']:
        ramsize = ((ramsize // main['memory_align']) + 1) * main['memory_align']
    if screen['nocolorram']:
        screen['colram'] = b''
        screen['colram_len'] = 0
    else:
        screen['colram'] = b''.join(screen['colram'])
        screen['colram_len'] = len(screen['colram'])
        if len(screen['colram']) < ramsize:
            screen['colram'] += bytes([0] * (ramsize - len(screen['colram'])))
    screen['colram_mem'] = len(screen['colram'])
    if len(screen['txtram']) < ramsize:
        screen['txtram'] += ascii2screen(screen['fillchar']) * (ramsize - len(screen['txtram']))
    screen['txtram_mem'] = len(screen['txtram'])
    screen['txtram_hex'] = hexify(screen['txtram'])
    screen['colram_hex'] = hexify(screen['colram'])
    screen['mainname'] = main['name']
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
        if screen['nocolorram']:
            screen['colram_start'] = 0
        else:
            screen['colram_start'] = addr
            addr += screen['colram_mem']
        sys.stdout.write('  %(_type)s %(screen)s: txt@%(txtram_start)06X, col@%(colram_start)06X\n' % screen)
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

def output_scr_header(main: dict):
    def _write(solo):
        fn = os.path.join(main['path'], main['filename'] + ('_solo.h' if solo else '.h'))
        with open(fn, 'wt') as outf:
            outf.write(SCREEN_BINH_HEADER % main)
            for screen in main['screens']:
                outf.write(SCREEN_BINH_TMPL % screen)
                for define in screen['defines']:
                    outf.write(define + '\n')
            if solo:
                outf.write('void %(name)s_init(void);\n\n#define %(cap_name)s_INIT %(name)s_init();\n' % main)
            else:
                outf.write('#define %(cap_name)s_INIT ;\n' % main)
            outf.write(SCREEN_BINH_FOOTER % main)
        sys.stdout.write(f'wrote {fn}\n')
    _write(0)
    _write(1)

def output_scr_code(main: dict):
    def _write(solo):
        fn = os.path.join(main['path'], main['filename'] + ('_solo.c' if solo else '.c'))
        with open(fn, 'wt') as outf:
            outf.write(SCREEN_BINC_HEADER % main)
            for screen in main['screens']:
                if screen['nocolorram']:
                    screen['nocol'] = '// '
                else:
                    screen['nocol'] = ''
                if solo:
                    outf.write(SCREEN_BINC_DATA_TMPL % screen)
                    screen['txtram_start_h'] = screen['colram_start_h'] = 0
                else:
                    screen['txtram_start_h'] = screen['txtram_start']
                    screen['colram_start_h'] = screen['colram_start']
                outf.write(SCREEN_BINC_STRUCT_TMPL % screen)
            if solo:
                outf.write('void %(name)s_init(void) {\n' % main)
                for screen in main['screens']:
                    outf.write('  %(mainname)s_%(screen)s.screen_start = (long)&%(mainname)s_%(screen)s_txtram;\n' % screen)
                    if not screen['nocolorram']:
                        outf.write('  %(mainname)s_%(screen)s.color_start = (long)&%(mainname)s_%(screen)s_colram;\n' % screen)
                outf.write('}\n')
            outf.write(SCREEN_BINC_FOOTER % main)
        sys.stdout.write(f'wrote {fn}\n')
    _write(0)
    _write(1)


class CustomHelpFormatter(argparse.HelpFormatter):

    def _fill_text(self, text, width, indent):
        import textwrap
        result = []
        for paragraph in re.split('\n\n\n+ *', text):
            if '\n\n' in paragraph:
                result.append('\n'.join([indent + line.strip(' ') for line in paragraph.split('\n\n')]))
                continue
            paragraph = self._whitespace_matcher.sub(' ', paragraph).strip()
            result.append(textwrap.fill(paragraph, width,
                                        initial_indent=indent,
                                        subsequent_indent=indent))
        return '\n\n'.join(result)


def main():
    parser = argparse.ArgumentParser(usage="MEGA65 Screen Builder", formatter_class=CustomHelpFormatter,
                                     description="""Generates screens and arrays of text and data in attic RAM, which can be accessed using mhexes screen functions.
                                     This saves a lot of code space. The definition file should use the .scr extension.\n\n
                                     The header of the definition file starts with key value pairs that are prefixed by @. You need to set either memory_start or memory_end and
                                     you can specify a memory_align a single screen is aligned to. In addition to that you can specify the base name of the generated files and
                                     names, otherwise this is derived from the .scr filename.\n\n
                                     Example:\n
\t@memory_end=0x4ffff\n
\t@memory_align=0x100\n
\t@filename=mf_screens\n\n
                                     After this a sequence of screens follow, which each consists of a header followed by a text section that is started with !text and ended with
                                     !endtext on a single line. A comment is a line starting with a # (hash sign). The screen must have a screen name, a size in characters
                                     (0 for line is autogenerated form the text), a background and foreground color, and definition of fillchar, array, and struct types.\n\n
                                     Example:\n
\t!screen=slot1_not_m65\n
\t!size=40x25\n
\t!background=6\n
\t!foreground=1\n
\t#123456789012345678901234567890123456789\n
\t!text\n
\t!endtext\n\n
                                     Lines are interpreted as text, except sequences in curly brackets, which are used to save the cursor position (C) or to set the foreground color
                                     (number or 3 letter appreviation). The lines are automatically trimmed to the screen size and filled with the fillchar (default space).\n\n
                                     If the array header is set, the fillchar defaults to EOS (end of string). In addition you can generate defines for the line numbers by using the
                                     '!idx LABELNAME' directive on a single line within the text. This generates '#define LABELNAME CURLINE' (CURLINE is replace by the current line)
                                     in the header files.\n\n
                                     Example:\n
\t!array=true\n
\t!text\n
\t!idx MFSC_CF_NO_ERROR\n
\t\n
\t!idx MFSC_CF_ERROR_OPEN\n
\tCould not open core file!\n
\t!idx MFSC_CF_ERROR_READ\n
\tFailed to read core file header!\n
\t!idx MFSC_CF_ERROR_SIG\n
\tCore signature not found!\n\n
                                     will generate:\n
\t#define MFSC_CF_NO_ERROR 0\n
\t#define MFSC_CF_ERROR_OPEN 1\n
\t#define MFSC_CF_ERROR_READ 2\n
\t#define MFSC_CF_ERROR_SIG 3\n\n
                                     You can also define that the data starts with a struct. The struct header takes a struct.pack format string (BB = two unsigned 8 bit values). To
                                     insert those values inside the text, use '{*NUMBER}'. NUMBER is parsed as an integer. The parsed data is prepended to the text.\n\n
                                     With the 'formatstring' switch you can make the screen a format string that can be used with mhx_writef. There is also a '{EOS}' format character
                                     to add end of string markers and you can save the current string position using {!LABELNAME}, to get character indexes inside the format string.\n\n
                                     Example:\n
\t!array=true\n
\t!struct=BB\n
\t!text\n
\t{*0x01}{*8}MEGA65 R1\n
\t{*0x02}{*4}MEGA65 R2\n
\t{*0x03}{*8}MEGA65 R3\n
                                     You can then copy the data into a struct to access it:\n\n
\ttypedef struct {\n
\t  uint8_t model_id;\n
\t  uint8_t slot_mb;\n
\t} mega_models_t;\n
\t...\n
\tchar buffer[80];\n
\tmhx_screen_get_line(&mf_screens_mega65_target, k++, (char *)&buffer);\n
\t((mega_models_t *)buffer)->model_id;\n
                                     """)
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
        'filename': filename.replace(".scr", ""),
        'name': filename.replace(".scr", "").replace('-', '_'),
        'cap_name': filename.replace(".scr", "").replace('-', '_').upper(),
        'screens': [],
    }
    SCREEN_TEMPLATE = {
        'screen': None,
        'size': (1, 1),
        'cursor_x': -1,
        'cursor_y': -1,
        'background': 0,
        'foreground': 1,
        'fillchar': ' ',
        'nocolorram': False,
        'array': False,
        'struct': '',
        'formatstring': False,
    }
    screen = {x: y for x, y in SCREEN_TEMPLATE.items()}
    screen['defines'] = []
    screen['structdata'] = []

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
                    sys.stdout.write('adding %(_type)s %(screen)s\n' % screen)
                    add_screen(main, screen)
                    screen = {x: y for x, y in SCREEN_TEMPLATE.items()}
                    screen['defines'] = []
                    screen['structdata'] = []
                    state = 2
    calc_memory(main)
    output_bin(main)
    output_scr_header(main)
    output_scr_code(main)

if __name__ == "__main__":
    main()
