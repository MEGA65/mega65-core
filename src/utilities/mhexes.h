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
 * NOTE: this is currently minted towards the 40x25
 * screen MEGAFLASH uses!
 *
 */

#include <cbm_screen_charmap.h>

// current attributes for writing to the screen (see MHX_A_*)
extern uint8_t mhx_curattr;
// border and background colour
extern uint8_t mhx_border, mhx_back;
// current position on the screen
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
  int32_t screen_start;
  // address of colour ram in memory
  int32_t color_start;
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
#define MHX_A_NOCOLOR   0x20 // don't change color ram
#define MHX_A_REVERT    0x40 // set non-inverse
#define MHX_A_INVERT    0x80 // set inverse
#define MHX_A_FLIP      0xc0 // flip between inverese and normal

// color and attribute strings
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

// color and attribute chars
#define MHX_C_EOS       0x80
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

// flags for mhx_check_input
#define MHX_CI_CHECKCASE 1 // also check character case
#define MHX_CI_PRINT 2 // print out typed characters

// flags for mhx_press_any_key
#define MHX_AK_ATTENTION 1 // colorcycle border while waiting
#define MHX_AK_NOMESSAGE 2 // dont' write "Press any key to continue\n"
#define MHX_AK_IGNORETAB 4 // ignore the TAB key
#define MHX_AK_NOCLEAR   8 // don't clear the keybuffer

/*
 * uint8_t mhx_ascii2screen(ascii, def)
 *
 * parameters:
 *   ascii: a ASCII character
 *   def: default screencode
 *
 * returns:
 *   screencode character
 *
 * this converts an ASCII (from mhx_getkeycode) into a
 * screencode. If the conversion is not possible, def is
 * returned instead.
 *
 */
uint8_t mhx_ascii2screen(uint8_t ascii, uint8_t def);

/*
 * uint16_t mhx_strlen(s)
 *
 * parameters:
 *   s: a string in screencode
 *
 * returns the length of the string s, up until
 * the terminating MHX_W_EOS (0x80).
 *
 */
uint16_t mhx_strlen(char *s);

/*
 * mhx_clearscreen(code, color)
 *
 * clear the screen using code character and color. Set
 * MHX_A_FLIP to color and clearscreen while wait for the
 * raster leave the screen.
 *
 */
void mhx_clearscreen(uint8_t code, uint8_t color);

/*
 * mhx_screencolor(back, border)
 *
 * parameters:
 *   back: background color (0-31)
 *   border: border color (0-31)
 *
 * side-effects:
 *   mhx_back: set to back
 *   mhx_border: set to border
 *
 * sets the screens background and border color
 *
 */
void mhx_screencolor(uint8_t back, uint8_t border);

/*
 * mhx_flashscreen(color, milli)
 *
 * parameters:
 *   color: flashcolor (0-31)
 *   delay: delay in milliseconds
 *
 * sets border and background to color of the screen
 * to color for delay milliseconds (usleep) and then
 * reverts to the colors set by mhx_screencolor before.
 *
 */
void mhx_flashscreen(uint8_t color, uint16_t delay);

/*
 * mhx_copyscreen(screen)
 *
 * parameters:
 *   screen: a screen definition in memory (see struct above)
 *
 * copies a predefined screen from attic ram into
 * screen memory and sets the current cursor position
 * using mhx_set_xy.
 *
 */
void mhx_copyscreen(mhx_screen_t *screen);

/*
 * mhx_hl_lines(line_start, line_end, attr)
 *
 * parameters:
 *   line_start: first  line to be effected
 *   line_end: last line to be effected
 *
 * modifies whole lines on the screen by applying attr
 * to them. This can change color, and also can invert
 * the characters (MHX_A_INVERT, MHX_A_REVERT, MHX_A_FLIP)
 *
 */
void mhx_hl_lines(uint8_t line_start, uint8_t line_end, uint8_t attr);

/*
 * mhx_draw_rect(ux, uy, width, height, title, attr, clear_inside)
 *
 * parameters:
 *   ux, uy: upper corner of the rect
 *   width, height: inside size of the rectangle
 *   title: string to display in the top left corner (NULL to skip)
 *   attr: attribute to draw the rectangle in (MHX_A_*)
 *   clear_inside: if true, also clear the inside of the rect and
 *                 apply attr to it
 *
 * draws a rectangle using PETSCII line charaters and optionally
 * places a title in the upper left corner. Can also clear the inside
 * of the rect.
 *
 */
void mhx_draw_rect(uint8_t ux, uint8_t uy, uint8_t width, uint8_t height, char *title, uint8_t attr, uint8_t clear_inside);

#define mhx_setattr(attr) mhx_curattr = attr

/*
 * mhx_set_xy(ux, uy)
 *
 * parameters:
 *   ux, uy: screen position
 *
 * side-effects:
 *   mhx_posx, mhx_posy: screen position
 *   mhx_saddr, mhx_caddr: ram pointer to screen and colorram
 *
 * sets the current screen position and calculates the new
 * position in ram for following commands.
 *
 */
void mhx_set_xy(uint8_t ux, uint8_t uy);

/*
 * mhx_move_xy(ux, uy)
 *
 * paramters:
 *   ux, uy: change in position (may be negative)
 *
 * side-effects:
 *   mhx_posx, mhx_posy: screen position
 *   mhx_saddr, mhx_caddr: ram pointer to screen and colorram
 *
 * changes the current cursor position and sets the ram
 * pointers accordingly. Can not move cursor out of the
 * screen.
 *
 */
void mhx_move_xy(int8_t ux, int8_t uy);

/*
 * mhx_advance_cursor(offset)
 *
 * parameters:
 *   offset: number of characters the cursor gets advanced
 *
 * side-effects:
 *   mhx_posx, mhx_posy: screen position
 *   mhx_saddr, mhx_caddr: ram pointer to screen and colorram
 *
 * advances the cursor a number of characters and optionally
 * scrolls the screen if the cursor moves out of the last
 * character of the last line.
 * Can't handle moves of more than a line!
 *
 */
void mhx_advance_cursor(uint8_t offset);

/*
 * mhx_write(text, attr)
 *
 * pramaters:
 *   text: a pointer to a string in screencode
 *   attr: a colorram attribute (MHX_A_*)
 *
 * write text at current position to the screen and
 * sets attributes accordingly. Uses mhx_advance_cursor.
 *
 * NOTE: MHX_W_* characters in text are not evaluated!
 *       Use mhx_writef for this.
 *
 */
void mhx_write(char *text, uint8_t attr);

/*
 * mhx_writef(format, ...)
 *
 * parameters:
 *   format: a format string in screencode with % formats
 *   ...: more stuff to format
 *
 * a poor mans printf. Does advance the cursor and scroll
 * the screen if needed, interprets MHX_W_* formatting.
 * Uses mhx_advance_cursor.
 *
 * Curently support the following format characters:
 *   %c: single character (screencode!)
 *   %s: a screencode string (EOS is 0x80!)
 *   %S: a ascii string (EOS 0x0) autoconverted
 *   %d, %u: decimal formatted number (non negative!)
 *   %b: binary formatted number
 *   %o: octal formatted number
 *   %x, %X: hexadecimal formatted number (X is uppercase)
 * Modifiers:
 *   number: number of places to format to
 *   leading '0': fill with zeroes instead of spaces
 *   'l': switch from 16 bit to 32 bit argument
 *
 */
void mhx_writef(char *format, ...);

/*
 * mhx_putch_offset(offset, screencode, attr)
 *
 * parameters:
 *   offset: cursor offset
 *   screencode: single character
 *   attr: colorram attributes (MHX_A_*)
 *
 * Puts one character on the screen at the current position
 * minus the offset and modifies colorram according to attr.
 *
 * NOTE: does not change current screen position!
 *
 */
void mhx_putch_offset(int8_t offset, uint8_t screencode, uint8_t attr);

#define mhx_putch(screencode, attr) mhx_putch_offset(0, screencode, attr)

#define mhx_write_xy(ux, uy, text, attr) mhx_set_xy(ux, uy); mhx_write(text, attr)

#define mhx_putch_xy(ux, uy, screencode, attr) mhx_set_xy(ux, uy); mhx_putch_offset(0, screencode, attr)

/*
 * mhx_clear_keybuffer()
 *
 * Clears the keyboard buffer.
 *
 */
void mhx_clear_keybuffer(void);

/*
 * mhx_keycode_t mhx_getkeycode(peekonly)
 *
 * parameters:
 *   peekonly: if true, don't wait for a character
 *
 * returns:
 *   mhx_keycode_t: struct containing ASCII code and
 *                  modifier bits
 *
 * gets the next keycode and modifier from the ASCII
 * keyboard buffer. This will wait until a key is
 * pressed, unless peekonly is true, in which case
 * it will return immdiatley with 0.
 *
 */
mhx_keycode_t mhx_getkeycode(uint8_t peekonly);

/*
 * bool mhx_check_input(match, flags, attr)
 *
 * parameters:
 *   match: a string (ASCII) expected
 *   flags: modifies behaviour (MHX_CI_*)
 *   attr: colorram attribute for printing (MHX_A_*)
 *
 * returns:
 *   0: user typed wrong character
 *   1: user typed what was expected in match
 *
 * waits for keypresses and compares them to match in
 * order (i.e. user must type what is in match) and
 * returns a bool value.
 *
 * Flags allow to not ignore character case and instruct
 * the function to also output the types characters
 * using mhx_putch.
 *
 */
uint8_t mhx_check_input(char *match, uint8_t flags, uint8_t attr);

/*
 * mhx_keycode_t mhx_press_any_key(flags, attr)
 *
 * parameters:
 *   flags: modify function behaviour (MHX_AK_*)
 *   attr: colorram attribute for "Press any key" message
 *
 * returns:
 *   mhx_keycode_t: struct containing ASCII code and
 *                  modifier bits
 *
 * waits for a keypress. Optionally writes
 * "Press any key to continue\n" to the screen (flag).
 * Returns the pressed keycode.
 *
 */
mhx_keycode_t mhx_press_any_key(uint8_t flags, uint8_t attr);

#endif /* MHEXES_H */
