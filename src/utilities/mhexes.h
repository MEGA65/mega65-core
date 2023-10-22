#ifndef MHEXES_H
#define MHEXES_H 1

#include <stdint.h>

/*
 * MHEXES v0.1
 *
 * set of routines that allow writing to the screen with
 * well known functions, without using the ROM to do it.
 *
 * Also allows input from the keyboard using ASCIIKEY
 * core input method.
 * 
 */

#include <cbm_screen_charmap.h>

// current attributes for writing to the screen (see MHX_A_*)
extern uint8_t mhx_curattr;
// border and background colour, current position in line
extern uint8_t mhx_border, mhx_back;
extern int8_t mhx_posx, mhx_posy;

// buffer for string formatting (used by mhx_writef)
extern char mhx_buffer[];

/*
 * definition of a preconstructed screen in memory
 *
 * used in conjunction with screenbuilder.py for
 * large quantity of text that can be loaded some
 * where else in memory without requiring code
 * space
 */
typedef struct {
  // number of bytes for screen and colour ram
  uint16_t screen_size, color_size;
  // position of the cursor after screen is written
  uint8_t cursor_x, cursor_y;
  // address of screen ram in memory
  long screen_start;
  // address of colour ram in memory
  long color_start;
} mhx_screen_t;

// keyboard modifier bitmasks
#define MHX_KEYMOD_RSHIFT 0b00000001
#define MHX_KEYMOD_LSHIFT 0b00000010
#define MHX_KEYMOD_SHIFT  0b00000011
#define MHX_KEYMOD_CTRL   0b00000100
#define MHX_KEYMOD_MEGA   0b00001000
#define MHX_KEYMOD_ALT    0b00010000
#define MHX_KEYMOD_NOSCRL 0b00100000
#define MHX_KEYMOD_CAPS   0b01000000

// keycode union (used by mhx_getch), see MHX_KEYMOD_*
typedef union {
  uint16_t keymod;
  struct {
    uint8_t key;
    uint8_t mod;
  } code;
} mhx_keycode_t;

// the last key read by mhx_getkeycode
extern mhx_keycode_t mhx_lastkey;

// Color attribute values
#define MHX_A_BLACK  0
#define MHX_A_WHITE  1
#define MHX_A_RED    2
#define MHX_A_CYAN   3
#define MHX_A_PURPLE 4
#define MHX_A_GREEN  5
#define MHX_A_BLUE   6
#define MHX_A_YELLOW 7
#define MHX_A_ORANGE 8
#define MHX_A_BROWN  9
#define MHX_A_LRED   10
#define MHX_A_DGREY  11
#define MHX_A_MGREY  12
#define MHX_A_LGREEN 13
#define MHX_A_LBLUE  14
#define MHX_A_LGREY  15
#define MHX_A_COLORMASK 0x1f
#define MHX_A_ATTRMASK  0xe0
#define MHX_A_NOCOLOR   0x20
#define MHX_A_REVERT    0x40
#define MHX_A_INVERT    0x80
#define MHX_A_FLIP      0xc0

#define MHX_C_EOS       0x80

// color and attribute codes
#define MHX_W_EOS    "\x0"
#define MHX_W_REVON  "\x81"
#define MHX_W_REVOFF "\x82"
#define MHX_W_CLRHOME "\x83"
#define MHX_W_HOME   "\x84"
#define MHX_W_BLACK  "\x90"
#define MHX_W_WHITE  "\x91"
#define MHX_W_RED    "\x92"
#define MHX_W_CYAN   "\x93"
#define MHX_W_PURPLE "\x94"
#define MHX_W_GREEN  "\x95"
#define MHX_W_BLUE   "\x96"
#define MHX_W_YELLOW "\x97"
#define MHX_W_ORANGE "\x98"
#define MHX_W_BROWN  "\x99"
#define MHX_W_LRED   "\x9a"
#define MHX_W_DGREY  "\x8b"
#define MHX_W_MGREY  "\x8c"
#define MHX_W_LGREEN "\x8d"
#define MHX_W_LBLUE  "\x8e"
#define MHX_W_LGREY  "\x8f"

#define MHX_C_DEFAULT '\x7f'
#define MHX_C_REVON  '\x81'
#define MHX_C_REVOFF '\x82'
#define MHX_C_CLRHOME '\x83'
#define MHX_C_HOME   '\x84'
#define MHX_C_BLACK  '\x90'
#define MHX_C_WHITE  '\x91'
#define MHX_C_RED    '\x92'
#define MHX_C_CYAN   '\x93'
#define MHX_C_PURPLE '\x94'
#define MHX_C_GREEN  '\x95'
#define MHX_C_BLUE   '\x96'
#define MHX_C_YELLOW '\x97'
#define MHX_C_ORANGE '\x98'
#define MHX_C_BROWN  '\x99'
#define MHX_C_LRED   '\x9a'
#define MHX_C_DGREY  '\x8b'
#define MHX_C_MGREY  '\x8c'
#define MHX_C_LGREEN '\x8d'
#define MHX_C_LBLUE  '\x8e'
#define MHX_C_LGREY  '\x8f'

uint8_t mhx_ascii2screen(uint8_t ascii, uint8_t def);

/*
 * clear_screen(code, color)
 *
 * clear the screen using code character and color
 */
void mhx_clearscreen(uint8_t code, uint8_t color);

void mhx_screencolor(uint8_t back, uint8_t border);

void mhx_flashscreen(uint8_t color, uint16_t milli);

void mhx_copyscreen(mhx_screen_t *screen);

void mhx_hl_lines(uint8_t line_start, uint8_t line_end, uint8_t attr);

void mhx_draw_rect(uint8_t ux, uint8_t uy, uint8_t width, uint8_t height, char *title, uint8_t attr);

#define mhx_setattr(attr) mhx_curattr = attr

void mhx_set_xy(uint8_t ux, uint8_t uy);

void mhx_move_xy(int8_t ux, int8_t uy);

void mhx_write(char *text, uint8_t attr);

void mhx_writef(char *format, ...);

void mhx_putch_offset(int8_t offset, uint8_t screencode, uint8_t attr);

#define mhx_putch(screencode, attr) mhx_putch_offset(0, screencode, attr)

#define mhx_write_xy(ux, uy, text, attr) mhx_set_xy(ux, uy); mhx_write(text, attr)

#define mhx_putch_xy(ux, uy, screencode, attr) mhx_set_xy(ux, uy); mhx_putch_offset(0, screencode, attr)

void mhx_clear_ch_buffer(void);

mhx_keycode_t mhx_getkeycode(void);

#define MHX_CI_CHECKCASE 1
#define MHX_CI_PRINT 2
uint8_t mhx_check_input(char *match, uint8_t flags, uint8_t attr);

#define MHX_AK_ATTENTION 1
#define MHX_AK_NOMESSAGE 2
#define MHX_AK_IGNORETAB 4
#define MHX_AK_NOCLEAR   8
mhx_keycode_t mhx_press_any_key(uint8_t flags, uint8_t attr);

#endif /* MHEXES_H */
