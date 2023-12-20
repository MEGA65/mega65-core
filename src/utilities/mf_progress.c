#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "mhexes.h"
#include "mf_progress.h"

/*
 * MEGAFLASH - Progress Bar
 *
 * Needed stuff:
 * - init progress
 * - update progress:
 *   - upwards
 *   - downwards
 *   - char groups (set X chars at pos Y), upwards and downwards
 * - update title
 */

// mfp_progress_direction 00 for upwards, ff for downwards
uint8_t mfp_progress_direction;
// y position where the progress bar starts
uint8_t mfp_progress_top;
uint8_t mfp_progress_lines;
// 16k block base progress
uint16_t mfp_progress_last;
uint8_t mfp_progress_attr;

// sub 64k progress in 16k blocks
uint8_t mfp_screencode_up[4] = { 0x7e, 0x61, 0x6c|0x80, 0xa0 };
uint8_t mfp_screencode_dn[4] = { 0xa0, 0x7b|0x80, 0x61|0x80, 0x7c };
uint8_t *mfp_screencode_cur;

/*
 * mfp_init_progress(uint8_t maxmb, uint8_t yp, uint8_t screencode, char *title, uint8_t attr)
 *
 * parameters:
 *   maxmb: maximum number of megabytes displayed, max is 8 MB
 *   yp: y-position of the window (40 chars wide)
 *   screencode: initial progress char displayed for all positions
 *   title: title string for the windows frame
 *   attr: attributes for the window (color)
 *
 * setup a progress window with a title at line yp (using mhexes)
 * the progress is always 8MB in size (4 lines of 32 screencodes, 64kB each)
 *
 */
void mfp_init_progress(uint8_t maxmb, uint8_t yp, uint8_t screencode, char *title, uint8_t attr)
{
  uint8_t i, j;

  // limit to 8M, so max 4 lines of progress
  if (maxmb > 8)
    maxmb = 8;

  mfp_progress_lines = maxmb >> 1;
  if (maxmb & 1) mfp_progress_lines++;

  mhx_draw_rect(0, yp, 38, mfp_progress_lines, title, attr, 1);
  for (i = 0; i < mfp_progress_lines; i++) {
    mhx_set_xy(1, yp + i + 1);
    mhx_writef("%XM ", i<<1);
    for (j = 0; j < ((i == mfp_progress_lines - 1 && maxmb & 1) ? 16 : 32); j++) {
      if (j && !(j & 0b111)) {
        mhx_putch('.', attr);
      }
      mhx_putch(screencode, attr);
    }
  }
  mfp_progress_top = yp + 1;
}

/*
 * void mfp_set_progress(uint8_t pos, uint8_t screencode, uint8_t attr)
 *
 * parameters:
 *   pos: the position inside the progress bar in 64k blocks
 *   screencode: the charater to set
 *   attr: attributes for the character
 *
 * sets a character with defined attributes at the selected position.
 *
 */
void mfp_set_progress(uint8_t pos, uint8_t screencode, uint8_t attr)
{
  // limit to 8M = 128 chars of 64K each
  pos &= 0x7f;
  mhx_set_xy(4 + (pos & 31) + ((pos & 31) >> 3), mfp_progress_top + (pos >> 5));
  mhx_putch(screencode, attr);
}

/*
 * void mfp_set_area(uint16_t start_block, uint16_t num_blocks, uint8_t screencode, uint8_t attr)
 *
 * set blocks progress chars to screencode starting at start_block upwards
 * this is used to set num_blocks in the display to a certain screencode,
 * like when erasing a block.
 * this does not update the overall progress counter!
 * does also only work on FULL chars, i.e. 64k blocks
 *
 * parameters:
 *   start_block: where the block starts in 64k blocks
 *   nun_blocks: number of 64 byte sectors that should be changed
 *   screencode: screencode to use
 *   attr: attributes for display
 *
 */
void mfp_set_area(uint16_t start_block, uint8_t num_blocks, uint8_t screencode, uint8_t attr)
{
  start_block &= 0x7f;
  while (num_blocks && start_block < 0x80) {
    mfp_set_progress(start_block++, screencode, attr);
    num_blocks--;
  }
}

/*
 * void mfp_start(last, direction, full_code, progress_attr title, attr)
 *
 * parameters:
 *   last: initial value for the start (as 32 bit address)
 *   direction: either MFP_DIR_UP or MFP_DIR_DOWN
 *   full_code: use this screencode for a filled block
 *   progress_attr: attribute for drawing progress chars
 *   title: title for the progress box
 *   attr: attribute for the title
 *
 * this starts a new progress *without* clearing the previous bar,
 * so you are writing progress over the previous.
 * It will change the title of the box and will set the direction the
 * bar progresses. It also sets the screencode for filled progress
 * boxes and the last progress value (0 for up and max for down?)
 *
 */
void mfp_start(uint32_t last, uint8_t direction, uint8_t full_code, uint8_t progress_attr, char *title, uint8_t attr)
{
  mhx_draw_rect(0, mfp_progress_top - 1, 38, mfp_progress_lines, title, attr, 0);
  mfp_progress_direction = direction == MFP_DIR_UP ? MFP_DIR_UP : MFP_DIR_DOWN;
  mfp_screencode_cur = direction == MFP_DIR_UP ? mfp_screencode_up : mfp_screencode_dn;
  mfp_set_progress_last(last);
  mfp_screencode_up[3] = mfp_screencode_dn[0] = full_code;
  mfp_progress_attr = progress_attr;
}

/*
 * void mfp_progress(addr)
 *
 * parameters:
 *   addr: current 32 bit address inside the progress
 *
 * updates the progress bar by drawing from mfp_progress_last
 * upto the current address 
 */
void mfp_progress(uint32_t addr)
{
  addr = (addr >> 14) & 0xffff;
  if (mfp_progress_last != (uint16_t)addr) {
    mfp_progress_last = (uint16_t)addr;
    mfp_set_progress(mfp_progress_last >> 2, mfp_screencode_cur[mfp_progress_last & 0x3], mfp_progress_attr);
    // mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
  }
}
