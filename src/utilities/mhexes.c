#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <string.h>

#include <memory.h>
#include <hal.h>

#include "mhexes.h"
#include "mhx_bin2scr.h"

#define mhx_base_scr 0x0400
#define mhx_base_col 0xd800
#define mhx_base_col24 0xff80000
#define mhx_scr_width 40
#define mhx_scr_height 25

uint16_t mhx_saddr = mhx_base_scr, mhx_caddr = mhx_base_col;

int8_t mhx_posx = 0, mhx_posy = 0;
uint8_t mhx_curattr = 0, mhx_border = 0, mhx_back = 0;

mhx_keycode_t mhx_lastkey;

char mhx_buffer[33];

#include <cbm_screen_charmap.h>

uint8_t mhx_ascii2screen(uint8_t ascii, uint8_t def)
{
  if (ascii < 0x20)
    return def;
  if (ascii == 0x40)
    return 0x00;
  if (ascii < 0x5f)
    return ascii;
  if (ascii == 0x5f) // underscore
    return 0x64;
  if (ascii == 0x60) // backtick
    return 0x7a;
  if (ascii < 0x7b)
    return ascii ^ 0x60;
  return def;
}

uint16_t mhx_strlen(char *s)
{
  uint16_t size = 0;

  for (size = 0; *s != MHX_C_EOS; size++, s++);

  return size;
}

void mhx_clearscreen(uint8_t code, uint8_t color)
{
  lfill((long)mhx_base_scr, code, mhx_scr_width*mhx_scr_height);
  lfill((long)mhx_base_col24, color, mhx_scr_width*mhx_scr_height);
  // memset((void *)mhx_base_scr, code, mhx_scr_width*mhx_scr_height);
  // memset((void *)mhx_base_col, color, mhx_scr_width*mhx_scr_height);
}

void mhx_screencolor(uint8_t back, uint8_t border)
{
  POKE(0xd020, border);
  POKE(0xd021, back);
  mhx_border = border;
  mhx_back = back;
}

void mhx_flashscreen(uint8_t color, uint16_t milli)
{
  POKE(0xd020, color);
  POKE(0xd021, color);
  usleep(milli * 1000L);
  POKE(0xd020, mhx_border);
  POKE(0xd021, mhx_back);
}

void mhx_hl_lines(uint8_t line_start, uint8_t line_end, uint8_t attr)
{
  if (line_end > mhx_scr_height || line_start > mhx_scr_height)
    return;
  if (line_end < line_start)
    line_end = line_start;
  line_end = (line_end - line_start + 1)*mhx_scr_width;
  mhx_set_xy(0, line_start);
  if (attr & MHX_A_FLIP) {
    for (line_start = 0; line_start < line_end; line_start++, mhx_saddr++)
      if ((attr & MHX_A_FLIP) == MHX_A_FLIP)
        POKE(mhx_saddr, PEEK(mhx_saddr) ^ 0x80);
      else if (attr & MHX_A_INVERT)
        POKE(mhx_saddr, PEEK(mhx_saddr) | 0x80);
      else if (attr & MHX_A_REVERT)
        POKE(mhx_saddr, PEEK(mhx_saddr) & 0x7f);
  }

  if (!(attr & MHX_A_NOCOLOR)) {
    memset((void *)mhx_caddr, attr & MHX_A_COLORMASK, line_end);
  }
}

void mhx_draw_rect(uint8_t ux, uint8_t uy, uint8_t width, uint8_t height, char *title, uint8_t attr, uint8_t clear_inside)
{
  // TODO: fix variables!
  uint8_t x;

  mhx_set_xy(ux, uy);
  POKE(mhx_saddr, 0x70 | (attr & MHX_A_INVERT));
  memset((void *)(mhx_saddr + 1), 0x40 | (attr & MHX_A_INVERT), width);
  POKE(mhx_saddr + width + 1, 0x6e | (attr & MHX_A_INVERT));
  if (title != NULL) {
    mhx_write_xy(ux + 2, uy, title, attr);
    mhx_set_xy(ux, uy);
  }
  if (clear_inside)
    memset((void *)mhx_caddr, attr & MHX_A_COLORMASK, width + 2);
  mhx_saddr += mhx_scr_width;
  mhx_caddr += mhx_scr_width;
  for (x = 0; x < height; x++, mhx_saddr += mhx_scr_width, mhx_caddr += mhx_scr_width) {
    POKE(mhx_saddr, 0x5d | (attr & MHX_A_INVERT));
    POKE(mhx_saddr + width + 1, 0x5d | (attr & MHX_A_INVERT));
    if (clear_inside) {
      memset((void *)(mhx_saddr + 1), 0x20 | (attr & MHX_A_INVERT), width);
      memset((void *)mhx_caddr, attr & MHX_A_COLORMASK, width + 2);
    }
  }
  POKE(mhx_saddr, 0x6d | (attr & MHX_A_INVERT));
  memset((void *)(mhx_saddr + 1), 0x40 | (attr & MHX_A_INVERT), width);
  POKE(mhx_saddr + width + 1, 0x7d | (attr & MHX_A_INVERT));
  if (clear_inside)
    memset((void *)mhx_caddr, attr & MHX_A_COLORMASK, width + 2);
}

void mhx_set_xy(uint8_t ux, uint8_t uy)
{
  if (ux >= mhx_scr_width || uy >= mhx_scr_height)
    return;
  mhx_saddr = ux + uy*mhx_scr_width;
  mhx_caddr = mhx_base_col + mhx_saddr;
  mhx_saddr += mhx_base_scr;
  mhx_posx = ux;
  mhx_posy = uy;
}

void mhx_move_xy(int8_t ux, int8_t uy)
{
  if (mhx_posx + ux < 0)
    ux = -mhx_posx;
  else if (mhx_posx + ux >= mhx_scr_width)
    ux = mhx_scr_width - mhx_posx - 1;
  if (mhx_posy + uy < 0)
    uy = -mhx_posy;
  else if (mhx_posy + uy >= mhx_scr_height)
    ux = mhx_scr_height - mhx_posy - 1;
  mhx_saddr += ux + uy*mhx_scr_width;
  mhx_caddr += ux + uy*mhx_scr_width;
  mhx_posx += ux;
  mhx_posy += uy;
}

void mhx_advance_cursor(uint8_t offset)
{
  if (mhx_posx + offset > mhx_scr_width)
    offset = mhx_scr_width - mhx_posx;
  mhx_saddr += offset;
  mhx_caddr += offset;
  mhx_posx += offset;
  if (mhx_posx >= mhx_scr_width) {
    mhx_posx = 0;
    mhx_posy++;
    // need to scroll
    if (mhx_posy >= mhx_scr_height) {
      lcopy((long)mhx_base_scr + mhx_scr_width, (long)mhx_base_scr, mhx_scr_width * (mhx_scr_height - 1));
      lcopy((long)mhx_base_col24 + mhx_scr_width, (long)mhx_base_col24, mhx_scr_width * (mhx_scr_height - 1));
      // need to clear the last line
      lfill((long)mhx_base_scr + mhx_scr_width * (mhx_scr_height - 1), ' ', mhx_scr_width);
      lfill((long)mhx_base_col24 + mhx_scr_width * (mhx_scr_height - 1), mhx_curattr, mhx_scr_width);
      mhx_saddr -= mhx_scr_width;
      mhx_caddr -= mhx_scr_width;
      mhx_posy--;
    }
  }
}

void mhx_write(char *text, uint8_t attr)
{
  while (*text != MHX_C_EOS) {
    POKE((void *)mhx_saddr, *text | (attr & MHX_A_INVERT));
    if (!(attr & MHX_A_NOCOLOR))
      POKE((void *)mhx_caddr, attr & MHX_A_COLORMASK);
    mhx_advance_cursor(1);
    text++;
  }
}

void mhx_writef(char *format, ...)
{
  char out, *sub = NULL;
  uint8_t mode = 0, count, pflags = 0, eos = MHX_C_EOS;
  uint32_t lval = 0;
  va_list args;
  va_start(args, format);

  while (*format != MHX_C_EOS) {
    if (mode == 0) {
      if (*format == '%') { // this is a format character following
        count = 0;
        if (format[1] == '0') {
          pflags = 0x10;
          format ++;
        }
        else
          pflags = 0;
        while (1) {
          format++;
          if (*format >= '0' && *format <= '9') {
            if (count < 20) {
              count *= 10;
              count += *format - '0';
            }
          }
          else if (*format == 'l')
            pflags |= 0x40;
          else
            break;
        }
        switch (*format) {
          case MHX_C_EOS: // % at the end is ok, exception
            out = '%';
            break;
          case '%':
            out = *format;
            format++;
            break;
          case 'c':
            out = va_arg(args, char);
            format++;
            break;
          case 'S': // autoconvert ASCII string to screencodes
            eos = 0;
          case 's':
            sub = va_arg(args, char *);
            if (*sub == eos) {
              // skip empty string
              format++;
              continue;
            }
            mode = 2;
            break;
          case 'd': // no signs in this code! yet anyway
          case 'u':
            pflags |= MHX_RDX_DEC | 0x20;
            break;
          case 'b':
            pflags |= MHX_RDX_BIN | 0x20;
            break;
          case 'o':
            pflags |= MHX_RDX_OCT | 0x20;
            break;
          case 'X':
            pflags |= MHX_RDX_UPPER;
          case 'x':
            pflags |= MHX_RDX_HEX | 0x20;
            break;
          default:
            break;
        }
        if (pflags & 0x20) {
          if (pflags & 0x40)
            lval = va_arg(args, uint32_t);
          else
            lval = (uint32_t) va_arg(args, uint16_t);
          count = mhx_bin2scr(pflags, count, lval, mhx_buffer);
          sub = mhx_buffer;
          mode = 2;
        }
      }
      else {
        out = *format;
        format++;
      }
    }
    // are we outputting s or S?
    if (mode == 2) {
      out = *sub;
      if (!eos)
        out = mhx_ascii2screen(out, MHX_C_DEFAULT);
      sub++;
      if (*sub == eos) {
        format++;
        mode = 0;
        eos = MHX_C_EOS;
      }
    }
    // handle special chars like newline
    if (out > 0x7f) {
      if (out >= 0x8b && out <= 0x9a)
        mhx_curattr = (mhx_curattr & MHX_A_ATTRMASK) | (out & 0xf);
      else
        switch (out) {
          case 0xca:
            mhx_advance_cursor(mhx_scr_width);
            break;
          case 0x81:
            mhx_curattr |= MHX_A_INVERT;
            break;
          case 0x82:
            mhx_curattr &= 0xff - MHX_A_INVERT;
            break;
          case 0x83:
            mhx_clearscreen(' ', mhx_curattr);
          case 0x84:
            mhx_set_xy(0, 0);
            break;
        }
      continue;
    }
    POKE((void *)mhx_saddr, out | (mhx_curattr & MHX_A_INVERT));
    if (!(mhx_curattr & MHX_A_NOCOLOR))
      POKE((void *)mhx_caddr, mhx_curattr & MHX_A_COLORMASK);
    mhx_advance_cursor(1);
  }
  va_end(args);
}

void mhx_putch_offset(int8_t offset, uint8_t screencode, uint8_t attr)
{
  POKE((void *)(mhx_saddr + offset), screencode | (attr & MHX_A_INVERT));
  if (!(attr & MHX_A_NOCOLOR))
    POKE((void *)(mhx_caddr + offset), attr & MHX_A_COLORMASK);
  if (!offset)
    mhx_advance_cursor(1);
}

void mhx_clear_ch_buffer(void)
{
  while (PEEK(0xD610))
    POKE(0xD610, 0);
}

mhx_keycode_t mhx_getkeycode(uint8_t peekonly)
{
  do {
    mhx_lastkey.code.key = PEEK(0xD610);
    mhx_lastkey.code.mod = PEEK(0xD611);
  } while (!mhx_lastkey.code.key && !peekonly);

  if (mhx_lastkey.code.key)
    POKE(0xD610, 0);

  return mhx_lastkey;
}

mhx_keycode_t mhx_press_any_key(uint8_t flags, uint8_t attr)
{
  if (!(flags & MHX_AK_NOMESSAGE))
    mhx_writef("Press any key to continue.\n", attr);

  if (!(flags & MHX_AK_NOCLEAR))
    mhx_clear_ch_buffer();
  do {
    mhx_lastkey.code.mod = PEEK(0xD611);
    if ((mhx_lastkey.code.key = PEEK(0xD610)))
      POKE(0xD610, 0);
    if (flags & MHX_AK_ATTENTION) // attention lets the border flash
      POKE(0xD020, (PEEK(0xD020) + 1) & 0xf);
  } while (mhx_lastkey.code.key == 0 || ((flags & MHX_AK_IGNORETAB) && mhx_lastkey.code.key == 0x09));

  if (flags & MHX_AK_ATTENTION)
    POKE(0xD020, mhx_border);

  return mhx_lastkey;
}

uint8_t mhx_check_input(char *match, uint8_t flags, uint8_t attr)
{
  mhx_clear_ch_buffer();

  while (*match) {
    // newline/RETURN fix
    if (*match == 0x0a)
      *match = 0x0d;

    mhx_getkeycode(0);
    if (mhx_lastkey.code.key != ((*match) & 0x7f)) {
      if (flags & MHX_CI_CHECKCASE)
        return 0;
      if (mhx_lastkey.code.key != ((*match ^ 0x20) & 0x7f))
        return 0;
    }
    if (flags & MHX_CI_PRINT)
      mhx_putch(mhx_ascii2screen(mhx_lastkey.code.key, 0), attr);
    match++;
  }

  return 1;
}

void mhx_copyscreen(mhx_screen_t *screen)
{
  // wait for raster leaving screen
  while (!(PEEK(0xD011)&0x80));

  // copy stuff
  lcopy(screen->screen_start, mhx_base_scr, screen->screen_size);
  lcopy(screen->color_start, mhx_base_col24, screen->color_size);

  // set cursor
  mhx_set_xy(screen->cursor_x, screen->cursor_y);
}

uint8_t mhx_progress_chars[4] = { 0x20, 0x65, 0x61, 0xe7 };
uint8_t mhx_progress, mhx_progress_last;
uint16_t mhx_progress_total, mhx_progress_goal;
