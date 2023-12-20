#ifndef MF_PROGRESS_H
#define MF_PROGRESS_H 1

#include <stdint.h>

/*
 * MEGAFLASH Progress Bar Helper
 *
 * This is a block based progress bar which can display
 * a segment of flash memory being flashed, showing the
 * various states of a memory block with some character
 * and/or color.
 *
 */

// diretion in which the bar is currently running
#define MFP_DIR_UP 0x00
#define MFP_DIR_DOWN 0xff

// access needed by mfp_set_progress_last macro
extern uint16_t mfp_progress_last;

// set last from a 32bit address
#define mfp_set_progress_last(addr) mfp_progress_last = (addr >> 14) & 0xffff

/*
 * mfp_init_progress(maxmb, yp, screencode, *title, attr)
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
void mfp_init_progress(uint8_t maxmb, uint8_t yp, uint8_t screencode, char *title, uint8_t attr);

/*
 * void mfp_set_area(start_block, num_blocks, screencode, attr)
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
void mfp_set_area(uint16_t start_block, uint8_t num_blocks, uint8_t screencode, uint8_t attr);

/*
 * void mfp_start(last, direction, full_code, progress_attr, *title, attr)
 *
 * parameters:
 *   last: initial value for the start (as 32 bit address)
 *   direction: either MFP_DIR_UP or MFP_DIR_DOWN
 *   full_code: use this screencode for a filled block
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
void mfp_start(uint32_t last, uint8_t direction, uint8_t full_code, uint8_t progress_attr, char *title, uint8_t attr);

/*
 * mfp_progress(addr)
 *
 * parameters:
 *   addr: a 32 bit address
 *
 * the progress bar is updated to match the current addr. This
 * is done by right shifting it 14 bit. mfp_progress_last is
 * updated by this.
 *
 */
void mfp_progress(uint32_t addr);

#endif /* MF_PROGRESS_H */
