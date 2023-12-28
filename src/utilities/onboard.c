#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include "qspireconfig.h"

short i, y;
unsigned char crt_mode = 1;
unsigned char last_video_mode = 0;
unsigned char video_mode_change_pending = 0;
unsigned char video_mode_frame_number = 0;
unsigned char video_mode = 0, c;
struct m65_tm tm;

char *month_name(int month)
{
  switch (month) {
  case 1:
    return "Jan";
  case 2:
    return "Feb";
  case 3:
    return "Mar";
  case 4:
    return "Apr";
  case 5:
    return "May";
  case 6:
    return "Jun";
  case 7:
    return "Jul";
  case 8:
    return "Aug";
  case 9:
    return "Sep";
  case 10:
    return "Oct";
  case 11:
    return "Nov";
  case 12:
    return "Dec";
  }
  return "???";
}

unsigned char frames;
unsigned char note;
unsigned char sid_num;
unsigned int sid_addr;
unsigned int notes[5] = { 5001, 5613, 4455, 2227, 3338 };

void test_audio(void)
{
  /*
    Play notes and samples through 4 SIDs and left/right digi
  */

  for (note = 0; note < 5; note++) {
    switch (note) {
    case 0:
      sid_num = 0;
      break;
    case 1:
      sid_num = 2;
      break;
    case 2:
      sid_num = 1;
      break;
    case 3:
      sid_num = 3;
      break;
    case 4:
      sid_num = 0;
      break;
    }

    sid_addr = 0xd400 + (0x20 * sid_num);

    // Play note
    POKE(sid_addr + 0, notes[note] & 0xff);
    POKE(sid_addr + 1, notes[note] >> 8);
    POKE(sid_addr + 4, 0x10);
    POKE(sid_addr + 5, 0x0c);
    POKE(sid_addr + 6, 0x00);
    POKE(sid_addr + 4, 0x11);

    // Wait 1/2 second before next note
    // (==25 frames)
    /*
       So the trick here, is that we need to decide if we are doing 4-SID mode,
       where all SIDs are 1/2 volume (gain can of course be increased to compensate),
       or whether we allow the primary pair of SIDs to be louder.
       We have to write to 4-SID registers at least every couple of frames to keep them active
    */
    for (frames = 0; frames < 35; frames++) {
      // Make sure all 4 SIDs remain active
      // by proding while waiting
      while (PEEK(0xD012U) != 0x80) {
        POKE(0xD438U, 0x0f);
        POKE(0xD478U, 0x0f);

        if (PEEK(0xD610))
          break;
        continue;
      }

      while (PEEK(0xD012U) == 0x80)
        continue;

      if (PEEK(0xD610))
        break;
    }
  }
}

void draw_dialog_box(void)
{
  POKE(0x0400 + 6 * 40 + 5, 112);
  for (i = 6; i < 35; i++)
    POKE(0x0400 + 6 * 40 + i, 0x40);
  POKE(0x0400 + 6 * 40 + 35, 110);
  for (i = 5; i < 36; i++)
    lpoke(0xFF80000 + 6 * 40 + i, 0x08);
  for (y = 7; y < 15; y++) {
    POKE(0x0400 + y * 40 + 5, 0x5d);
    for (i = 6; i < 35; i++)
      POKE(0x0400 + y * 40 + i, 0x20);
    POKE(0x0400 + y * 40 + 35, 0x5d);
    for (i = 5; i < 36; i++)
      lpoke(0xFF80000 + y * 40 + i, 0x08);
  }
  POKE(0x0400 + 15 * 40 + 5, 109);
  for (i = 6; i < 35; i++)
    POKE(0x0400 + 15 * 40 + i, 0x40);
  POKE(0x0400 + 15 * 40 + 35, 125);
  for (i = 5; i < 36; i++)
    lpoke(0xFF80000 + 15 * 40 + i, 0x08);
}

unsigned char last_frame_number = 0;
unsigned short time_left = 0;

void confirm_video_mode_change(void)
{

  // First backup screen and colour RAM
  lcopy(0x0400, 0x12000, 1000);
  lcopy(0xff80000, 0x12400, 1000);

  draw_dialog_box();

  POKE(0x0286, 7);
  printf("\023\n\n\n\n\n\n"
         "\035\035\035\035\035\035Try video mode:\n"
         "\035\035\035\035\035\035  ");
  POKE(0x286, 1);
  switch (video_mode) {
  case 0:
    printf("NTSC, Pure DVI");
    break;
  case 1:
    printf("PAL, Pure DVI");
    break;
  case 2:
    printf("NTSC, Digital Audio");
    break;
  case 3:
    printf("PAL, Digital Audio");
    break;
  }
  printf("\n\n\035\035\035\035\035\035(Will revert on fail after\n"
         "\035\035\035\035\035\03515 seconds.)");
  printf("\n"
         "\035\035\035\035\035\035        (Y)es or (N)o?");

  while (PEEK(0xD610))
    POKE(0xD610, 0);
  while (!PEEK(0xD610))
    continue;

  switch (PEEK(0xD610)) {
  case 0x59:
  case 0x79: // Y

    POKE(0xD610, 0);

    // Set video mode

    // NTSC / PAL
    if (video_mode & 1)
      POKE(0xD06F, 0x00);
    else
      POKE(0xD06F, 0x80);
    // DVI / Enhanced
    if (video_mode & 2)
      POKE(0xD61A, 0x00);
    else
      POKE(0xD61A, 0x02);
    POKE(0xD011, 0x1b);

    // Draw "Press K to keep new video mode" dialog
    draw_dialog_box();

    POKE(0x0286, 7);
    printf("\023\n\n\n\n\n\n"
           "\035\035\035\035\035\035Press K to keep video mode.\n");

    time_left = 50 * 15;
    last_frame_number = PEEK(0xD7FA);
    while (!PEEK(0xD610)) {
      printf("\023\n\n\n\n\n\n\n\n"
             "\035\035\035\035\035\035Timeout in %2d sec.",
          time_left / 50);
      if (last_frame_number != PEEK(0xD7FA)) {
        last_frame_number = PEEK(0xD7FA);
        time_left--;
      }
      if (!time_left)
        break;
    }
    switch (PEEK(0xD610)) {
    case 0x4b:
    case 0x6b:
      POKE(0xD610, 0);
      // Keep new mode
      lcopy(0x12000, 0x0400, 1000);
      lcopy(0x12400, 0xff80000, 1000);
      return;
    default:
      // Revert and restore

      POKE(0xD610, 0);

      //	video_mode=last_video_mode;
      // NTSC / PAL
      if (video_mode & 1)
        POKE(0xD06F, 0x00);
      else
        POKE(0xD06F, 0x80);
      // DVI / Enhanced
      if (video_mode & 2)
        POKE(0xD61A, 0x00);
      else
        POKE(0xD61A, 0x02);
      POKE(0xD011, 0x1b);
      // Restore screen
      lcopy(0x12000, 0x0400, 1000);
      lcopy(0x12400, 0xff80000, 1000);
    }

    break;
  default:
    POKE(0xD610, 0);

    // Don't try: Revert and restore
    lcopy(0x12000, 0x0400, 1000);
    lcopy(0x12400, 0xff80000, 1000);
    //      video_mode=last_video_mode;
  }
}

void audiomix_setcoefficient(unsigned char co, unsigned char v)
{
  unsigned char c;
  POKE(0xD6F4, co);
  // Wait 16 cycles (the following certainly is longer than that
  for (c = 0; c < 4; c++)
    continue;
  POKE(0xD6F5, v);
}

unsigned char mix_coeff[256] = { 0xbf, 0xbf, 0x40, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00,
  0x00, 0xbf, 0xbf, 0x40, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,

  0x40, 0x40, 0xbf, 0xbf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x40, 0x40, 0xbf, 0xbf,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff,

  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff,

  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,

  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,

  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,

  0xbf, 0xbf, 0x40, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0xbf, 0xbf, 0x40, 0x40,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff,

  0x40, 0x40, 0xbf, 0xbf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x40, 0x40, 0xbf, 0xbf,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff };

void audiomix_setup(void)
{
  // Mirrors what audiomix.asm in HYPPO does
  unsigned short c;

  // Clear all coefficients by default
  for (c = 0; c < 256; c++) {
    audiomix_setcoefficient(c, mix_coeff[c]);
  }

  // Reset all sids
  lfill(0xffd3400, 0, 0x100);

  // Full volume on all SIDs
  POKE(0xD418U, 0x0f);
  POKE(0xD438U, 0x0f);
  POKE(0xD458U, 0x0f);
  POKE(0xD478U, 0x0f);
}

void hw_setup_r4rtc(void)
{
  // enable SuperCAP charging, if not done yet
  if (lpeek(0xffd71d0UL) == 0x22)
    return;

  // disable eeprom refresh
  lpoke(0xffd7120UL, 0x04);
  usleep(20000L); // need to wait for slow RTC getting updated
  // set backup switchover mode to LSM, TCM 3V (Battery protection)
  lpoke(0xffd71d0UL, 0x22);
  usleep(20000L);
  // EECMD Update EEPROM
  lpoke(0xffd714fUL, 0x11);
  usleep(20000L);
  // enable eeprom refresh
  lpoke(0xffd7120UL, 0x00);
  usleep(20000L);
}

void hardware_setup(void)
{
  switch (PEEK(0xD629)) {
    case 0x04:
    case 0x05:
    case 0x06:
      hw_setup_r4rtc();
      break;
  }
}

void main(void)
{
  unsigned char idle_time = 0, update_rtc = 0;

  mega65_io_enable();

  // Disable OSK
  lpoke(0xFFD3615L, 0x7F);

  // Enable VIC-III attributes
  POKE(0xD031, 0x20);

  // Disable CRT emulation to begin with
  POKE(0xD054, 0);

  // Ensure screen colours right
  POKE(0xD020, 6);
  POKE(0xD021, 6);
  POKE(0x286, 0x01);

  // Reset audio mixer coefficients
  audiomix_setup();

  // do hardware version dependent setup
  hardware_setup();

  printf("%cWelcome to the MEGA65!\n\n"
         "Before you go further, there are couple of things you need to do.\n\n"
         "Press F3 - F13 to set the time and date (shift toggles direction).", 0x93);

  getrtc(&tm);

  while (1) {
    POKE(0x286, 1);
    printf("%c\n\n\n\n\n", 0x13);

    POKE(0x286, 1);
    printf("\nTime:  ");
    POKE(0x286, 7);
    if (tm.tm_sec < 61) {
      printf("%c%02d-%s-%04d %02d:%02d:%02d%c  ", 0x12, tm.tm_mday, month_name(tm.tm_mon),
          tm.tm_year + 1900, tm.tm_hour, tm.tm_min, tm.tm_sec, 0x92);
    }
    POKE(0x286, 14);
    printf("\n       F9 F11 F13  F3 F5 F7\n");
    POKE(0x286, 1);
    printf("\n\n");

    printf("Video: %c", 0x12);
    POKE(0x286, 7);
    switch (video_mode) {
    case 0:
      printf("DVI (no sound), NTSC 60Hz       ");
      break;
    case 1:
      printf("DVI (no sound), PAL 50Hz        ");
      break;
    case 2:
      printf("Enhanced (with sound), NTSC 60Hz");
      break;
    case 3:
      printf("Enhanced (with sound), PAL 50Hz ");
      break;
    }
    printf("%c\n", 0x92);
    POKE(0x286, 14);
    printf("       TAB = cycle through modes\n");
    printf("       SPACE = apply and test mode.\n");

    POKE(0x286, 1);
    printf("\n\nTest Audio (set video mode first): ");
    POKE(0x286, 14);
    printf("\n       A = play a tune\n");

    POKE(0x286, 1);
    printf("\n\nCRT Emulation: %c", 0x12);
    POKE(0x286, 7);
    switch (crt_mode) {
    case 0:
      printf("Disabled");
      break;
    case 1:
      printf("Enabled ");
      break;
    }
    printf("%c\n", 0x92);
    POKE(0x286, 14);
    printf("               C = toggle\n");

    POKE(0x286, 1);
    printf("\nPress ");
    POKE(0x286, 3);
    printf("%cRETURN%c", 0x12, 0x92);
    POKE(0x286, 1);
    printf(" to save and exit.");

    c = PEEK(0xD610);
    if (!c) {
      if (idle_time < 75)
        idle_time++;
      if (idle_time == 75) {
        if (update_rtc) {
          setrtc(&tm);
          usleep(950000UL);
          update_rtc = 0;
        }
        else
          getrtc(&tm);
        idle_time = 0;
      }
      usleep(10000UL);
      continue;
    }
    idle_time = 0;
    POKE(0xD610, 0);

    switch (c) {
    case 0x41:
    case 0x61:
      POKE(0xD020, 0);
      test_audio();
      POKE(0xD020, 6);
      break;
    case 0x43:
    case 0x63:
      // Toggle CRT emulation
      crt_mode ^= 1;
      if (crt_mode)
        POKE(0xD054, 0x20);
      else
        POKE(0xD054, 0x00);
      break;
    case 0x1F:
      // HELP key
      video_mode = 0;
      video_mode_change_pending = 1;

      // Make restoration of video mode take effect immediately

      // NTSC
      POKE(0xD06F, 0x80);
      // DVI
      POKE(0xD61A, 0x02);
      POKE(0xD011, 0x1b);

      video_mode_change_pending = 0;
      last_video_mode = video_mode;

      break;
    case 0x09:
      video_mode++;
      video_mode &= 0x03;

      if (video_mode != last_video_mode)
        video_mode_change_pending = 1;
      else
        video_mode_change_pending = 0;
      video_mode_frame_number = PEEK(0xD7FA) - 1;

      break;
    case 0x20:
      confirm_video_mode_change();
      video_mode_change_pending = 0;
      break;
    case 0xF3:
    case 0xF4:
      if (c & 1)
        tm.tm_hour++;
      else
        tm.tm_hour--;
      if (tm.tm_hour > 127)
        tm.tm_hour = 23;
      if (tm.tm_hour > 23)
        tm.tm_hour = 0;
      update_rtc = 1;
      break;
    case 0xF5:
    case 0xF6:
      if (c & 1)
        tm.tm_min++;
      else
        tm.tm_min--;
      if (tm.tm_min > 127)
        tm.tm_min = 59;
      if (tm.tm_min > 59)
        tm.tm_min = 0;
      update_rtc = 1;
      break;
    case 0xF7:
    case 0xF8:
      if (c & 1)
        tm.tm_sec++;
      else
        tm.tm_sec--;
      if (tm.tm_sec > 127)
        tm.tm_sec = 59;
      if (tm.tm_sec > 59)
        tm.tm_sec = 0;
      update_rtc = 1;
      break;
    case 0xF9:
    case 0xFA:
      if (c & 1)
        tm.tm_mday++;
      else
        tm.tm_mday--;
      if (!tm.tm_mday)
        tm.tm_mday = 31;
      if (tm.tm_mday > 127)
        tm.tm_mday = 31;
      switch (tm.tm_mon) {
      case 2:
        if (tm.tm_mday > 29)
          tm.tm_mday = 1;
        // year is minus 1900, so 100 is 2000 (no leap year), and we
        // do not need to check 500, as the RTC can't do this.
        if (tm.tm_year & 3 || tm.tm_year == 100) {
          if (tm.tm_mday > 28)
            tm.tm_mday = 1;
        }
        break;
      case 4:
      case 6:
      case 9:
      case 11:
        if (tm.tm_mday > 30)
          tm.tm_mday = 1;
        break;
      default:
        if (tm.tm_mday > 31)
          tm.tm_mday = 1;
      }
      update_rtc = 1;
      break;
    case 0xFB:
    case 0xFC:
      if (c & 1)
        tm.tm_mon++;
      else
        tm.tm_mon--;
      if (!tm.tm_mon)
        tm.tm_mon = 12;
      if (tm.tm_mon > 127)
        tm.tm_mon = 12;
      if (tm.tm_mon > 12)
        tm.tm_mon = 1;
      // Clip date to fit month
      switch (tm.tm_mon) {
      case 2:
        if (tm.tm_mday > 29)
          tm.tm_mday = 29;
        // year is minus 1900, so 100 is 2000 (no leap year), and we
        // do not need to check 500, as the RTC can't do this.
        if (tm.tm_year & 3 || tm.tm_year == 100) {
          if (tm.tm_mday > 28)
            tm.tm_mday = 28;
        }
        break;
      case 4:
      case 6:
      case 9:
      case 11:
        if (tm.tm_mday > 30)
          tm.tm_mday = 30;
        break;
      }
      update_rtc = 1;
      break;
    case 0x42:
    case 0x62:
      for (i = 0; i < 256; i++)
        POKE(0x0400 + i, i);

      break;
    case 0xFD:
    case 0xFE:
      if (c & 1)
        tm.tm_year++;
      else
        tm.tm_year--;
      if (tm.tm_year > 299)
        tm.tm_year = 0;
      update_rtc = 1;
      break;
    case 0x0d:
    case 0x0a:
      // Return = save settings and proceed.
      /*
        We write a valid default configuration sector.
      */

      // this also sets the time
      if (update_rtc) {
        setrtc(&tm);
        usleep(950000UL);
      }

      if (video_mode_change_pending) {
        // If we have a video mode change pending, try it now
        confirm_video_mode_change();
        video_mode_change_pending = 0;
        last_video_mode = video_mode;
      }
      else {

        // First make sure we have the config sector freshly loaded
        lpoke(0xffd3681, 0x01);
        lpoke(0xffd3682, 0x00);
        lpoke(0xffd3683, 0x00);
        lpoke(0xffd3684, 0x00);
        lpoke(0xffd3680, 0x02);
        while (lpeek(0xffd3680) & 0x03)
          continue;

        // Write version header
        lpoke(0xffd6e00, 0x01);
        lpoke(0xffd6e01, 0x01);

        // Write PAL/NTSC flag
        if (video_mode & 1)
          lpoke(0xffd6e02, 0x00);
        else
          lpoke(0xffd6e02, 0x80);
        // Write DVI/audio enable flag
        if (video_mode & 2)
          lpoke(0xffd6e0d, 0x00);
        else
          lpoke(0xffd6e0d, 0x02);

        // Write CRT emulation byte
        if (crt_mode)
          lpoke(0xffd6e21, 0x20);
        else
          lpoke(0xffd6e21, 0x00);

        // Enforce lfn support now
        lpoke (0xffd6e0f, 0x80);

        // Write onboarding complete byte
        lpoke(0xffd6e0e, 0x80);

        // write config sector back
        lpoke(0xffd3680, 0x57); // open write gate
        lpoke(0xffd3680, 0x03); // actually write the sector
        while (lpeek(0xffd3680) & 0x03)
          continue;

        // Now restart by reconfiguring the FPGA -- DONT DO THAT!
        // as this will start slot 0
        // reconfig_fpga(0);

        printf("%c\n\n\n\n\n\n\n\n\n\n\n"
               "   Please POWER-CYCLE your MEGA65 now\n"
               "    by turning it off and on again!", 0x93);
        while (1);
      }
    }
  }
}
