unsigned char user_has_been_warned(void)
{
  printf("%c"
      "Replacing the bitstream in slot 0 can\n"
      "brick your MEGA65. If you are REALLY\n"
      "SURE that you want to do this, type:\n"
      "I ACCEPT THIS VOIDS MY WARRANTY\n",
      0x93);
  if (!check_input("I ACCEPT THIS VOIDS MY WARRANTY\r", CASE_SENSITIVE)) return 0;
  printf("\nAnd now:\n"
      "ITS MY FAULT ALONE WHEN IT GOES WRONG\n");
  if (!check_input("ITS MY FAULT ALONE WHEN IT GOES WRONG\r", CASE_SENSITIVE)) return 0;
  printf("\nAlso, type in the 32768th prime:\n");
  if (!check_input("386093\r", CASE_SENSITIVE)) return 0;
  printf("\nFinally, what is the average airspeed of"
      " a laden (european) swallow?\n");
  if (!check_input("11 METRES PER SECOND\r", CASE_SENSITIVE)) return 0;
  return 1;
}
