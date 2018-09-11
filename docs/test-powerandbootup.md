## Power and BOOT-up

* Power up the board:  
ensure that the host-PC is providing power through the USB cable, and that the POWER switch is ON.  
-> Host-PC should show some output generated from the SerialDebugger.  
-> Boot sequence is: approx 3-secs of boot-display (black screen with white text), then falls into c65 mode.  
-> verify that the VGA screen shows the same as below:  
![alt tag](https://raw.githubusercontent.com/Ben-401/mega65pics/master/c65mode.jpg)  

* Reset the board:  
press and release the "CPU_RESET" button.  
-> during the approx 3-secs of boot-display, the LCD should display ``4800 4502``.  
-> when in c65 mode, the LCD should display ``0400 4502``.  

* reprogram the board:  
press and release the "PROG" button.  
-> (results are the same as the above test)  
-> during the approx 3-secs of boot-display, the LCD should display ``4800 4502``.  
-> when in c65 mode, the LCD should display ``0400 4502``.  

* hold the boot-screen:  
assert SW-15 (switch 15 on the far LHS) by pushing it UP,  
press and release the "PROG" button.  
-> boot screen should be displayed,  
-> after boot-up, a message at the top of the screen should be displayed "RELEASE SW-15 TO CONTINUE BOOTING."  
-> verify the text of the boot-screen is similar to the below:  
![alt tag](https://raw.githubusercontent.com/Ben-401/mega65pics/master/bootscreen.jpg)  

* display debug output:  
assert SW-15 and SW-12 by pushing them UP/ON,  
press and release the "PROG" button.  
-> boot screen should be displayed,  
-> during boot, a number of text lines will be displayed (and sent via serial-cooms to the host-PC),  
-> after boot-up, a message at the top of the screen should be displayed "RELEASE SW-15 TO CONTINUE BOOTING."  
-> verify the text of the boot-screen is similar to the above:  
-> verify the text of the serial-comms is similar to the below:  
```
MEGA65 Serial Monitor
build merge-,550ca13+DIRTY,0316-1352
--------------------------------
See source code for help.

.Checkpoint @ $99B6 A:$0C, X:$00, Y:$10, Z:$00, P:$37 :reset_machine_state
Checkpoint @ $99CE A:$0C, X:$00, Y:$10, Z:$00, P:$35 :reset_machine_state
Checkpoint @ $B073 A:$31, X:$31, Y:$30, Z:$00, P:$34 :dos_disk_count = 01
Checkpoint @ $ABBD A:$30, X:$30, Y:$31, Z:$00, P:$34 :current file desc=01, and offset=10.
Checkpoint @ $9756 A:$00, X:$00, Y:$15, Z:$00, P:$36 :Resetting SDCARD
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00000000.
Checkpoint @ $8B80 A:$02, X:$30, Y:$30, Z:$00, P:$37 :dos_clearall:
Checkpoint @ $8716 A:$00, X:$00, Y:$30, Z:$00, P:$37 :Reading MBR @ 0x00000000
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00000000.
Checkpoint @ $860F A:$AA, X:$30, Y:$30, Z:$00, P:$37 :Found $55AA at $1FE on MBR
Checkpoint @ $8638 A:$DF, X:$30, Y:$30, Z:$00, P:$B5 :=== Checking Partition #1 at $01BE
Checkpoint @ $8759 A:$0C, X:$30, Y:$04, Z:$00, P:$37 :Partn has fat32_lba (type=0x0c)
Checkpoint @ $8878 A:$00, X:$08, Y:$10, Z:$00, P:$37 :dos_disk_openpartition: (examine Vol ID)
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00000800.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00100000.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00100000.
Checkpoint @ $88F0 A:$AA, X:$30, Y:$30, Z:$00, P:$37 :Partn has $55AA GOOD
Checkpoint @ $8A52 A:$0F, X:$FF, Y:$08, Z:$01, P:$34 :FAT32 partition data copied to dos_disk_table
Checkpoint @ $AE62 A:$00, X:$FF, Y:$08, Z:$01, P:$37 :dos_disk_table
Checkpoint @ $AED5 A:$30, X:$30, Y:$30, Z:$01, P:$34 :00,08,00,00,00,A0,0F,00
Checkpoint @ $AF51 A:$32, X:$32, Y:$30, Z:$01, P:$34 :0F,E6,03,00,00,38,02,02
Checkpoint @ $AFCD A:$32, X:$32, Y:$30, Z:$01, P:$34 :02,00,BF,F2,01,00,08,02
Checkpoint @ $B049 A:$30, X:$30, Y:$30, Z:$01, P:$34 :04,0A,00,00,00,00,00,00
Checkpoint @ $880B A:$31, X:$31, Y:$30, Z:$01, P:$34 :Part#1 NOT set to the default_disk
Checkpoint @ $8716 A:$00, X:$31, Y:$30, Z:$01, P:$37 :Reading MBR @ 0x00000000
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$01, P:$34 :sd_sector: $d681=00000000.
Checkpoint @ $866D A:$CE, X:$30, Y:$30, Z:$01, P:$B5 :=== Checking Partition #2 at $01CE
Checkpoint @ $8834 A:$01, X:$30, Y:$04, Z:$01, P:$34 :Partition not interesting
Checkpoint @ $8716 A:$00, X:$30, Y:$04, Z:$01, P:$37 :Reading MBR @ 0x00000000
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$01, P:$34 :sd_sector: $d681=00000000.
Checkpoint @ $86A2 A:$DE, X:$30, Y:$30, Z:$01, P:$B5 :=== Checking Partition #3 at $01DE
Checkpoint @ $8834 A:$01, X:$30, Y:$04, Z:$01, P:$34 :Partition not interesting
Checkpoint @ $8716 A:$00, X:$30, Y:$04, Z:$01, P:$37 :Reading MBR @ 0x00000000
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$01, P:$34 :sd_sector: $d681=00000000.
Checkpoint @ $86D7 A:$EE, X:$30, Y:$30, Z:$01, P:$B5 :=== Checking Partition #4 at $01EE
Checkpoint @ $8834 A:$01, X:$30, Y:$04, Z:$01, P:$34 :Partition not interesting
Checkpoint @ $B073 A:$31, X:$31, Y:$30, Z:$00, P:$34 :dos_disk_count = 01
Checkpoint @ $ABBD A:$30, X:$30, Y:$31, Z:$00, P:$34 :current file desc=01, and offset=10.
Checkpoint @ $8AB6 A:$30, X:$30, Y:$30, Z:$00, P:$34 :dos_set_current_disk=00
Checkpoint @ $9AE5 A:$00, X:$95, Y:$0C, Z:$00, P:$37 :  try-loading BOOTLOGO
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8C3F A:$02, X:$30, Y:$30, Z:$00, P:$37 :-
Checkpoint @ $8C67 A:$30, X:$30, Y:$30, Z:$00, P:$34 :dos_readdir[0000]==========================================
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $ACA7 A:$30, X:$30, Y:$30, Z:$00, P:$34 :FileDesc<=00,80,02,00,00,00,02,00 - 00,00,00,00,00,00,00,00
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8D1D A:$43, X:$0B, Y:$34, Z:$00, P:$34 : (8.3)+(ATTRIB)+(NAME[0]) = LOUD        08 4C
Checkpoint @ $8DB6 A:$00, X:$0B, Y:$08, Z:$00, P:$37 : is Volume ID, so skip this record
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8C3F A:$02, X:$30, Y:$30, Z:$00, P:$37 :-
Checkpoint @ $8C67 A:$30, X:$30, Y:$30, Z:$00, P:$34 :dos_readdir[0020]==========================================
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $ACA7 A:$30, X:$30, Y:$30, Z:$00, P:$34 :FileDesc<=00,80,02,00,00,00,02,00 - 00,00,00,20,00,00,00,00
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8D1D A:$33, X:$0B, Y:$34, Z:$00, P:$34 : (8.3)+(ATTRIB)+(NAME[0]) = C~?.?b?i?t? 0F 43
Checkpoint @ $8E22 A:$1A, X:$1A, Y:$00, Z:$00, P:$34 :BGOK drce_next_piece: found LFN piece
Checkpoint @ $8E94 A:$00, X:$1F, Y:$0E, Z:$06, P:$36 :BGOK drce_eot_in_filename
Checkpoint @ $8EC6 A:$00, X:$1F, Y:$0E, Z:$06, P:$36 :BGOK drce_ignore_lfn_piece
Checkpoint @ $8EE5 A:$00, X:$1F, Y:$0E, Z:$06, P:$35 :BGOK drce_cont_next
Checkpoint @ $8D1D A:$32, X:$0B, Y:$30, Z:$06, P:$34 : (8.3)+(ATTRIB)+(NAME[0]) = ?e?r?g?e?-? 0F 02
Checkpoint @ $8E22 A:$0D, X:$0D, Y:$00, Z:$06, P:$34 :BGOK drce_next_piece: found LFN piece
Checkpoint @ $8E94 A:$33, X:$1A, Y:$20, Z:$00, P:$36 :BGOK drce_eot_in_filename
Checkpoint @ $8EC6 A:$00, X:$1A, Y:$20, Z:$00, P:$36 :BGOK drce_ignore_lfn_piece
Checkpoint @ $8EE5 A:$00, X:$1A, Y:$20, Z:$00, P:$35 :BGOK drce_cont_next
Checkpoint @ $8D1D A:$31, X:$0B, Y:$30, Z:$00, P:$34 : (8.3)+(ATTRIB)+(NAME[0]) = ?b?i?t?0?3? 0F 01
Checkpoint @ $8E22 A:$00, X:$00, Y:$00, Z:$00, P:$36 :BGOK drce_next_piece: found LFN piece
Checkpoint @ $8E94 A:$6D, X:$0D, Y:$20, Z:$00, P:$36 :BGOK drce_eot_in_filename
Checkpoint @ $8EC6 A:$00, X:$0D, Y:$20, Z:$00, P:$36 :BGOK drce_ignore_lfn_piece
Checkpoint @ $8EE5 A:$00, X:$0D, Y:$20, Z:$00, P:$35 :BGOK drce_cont_next
Checkpoint @ $8D1D A:$32, X:$0B, Y:$34, Z:$00, P:$34 : (8.3)+(ATTRIB)+(NAME[0]) = BIT031~1BIT 20 42
Checkpoint @ $8F30 A:$00, X:$0B, Y:$20, Z:$00, P:$37 : processing SHORT-name
Checkpoint @ $8FDC A:$20, X:$04, Y:$0B, Z:$00, P:$35 : drce_fl populated fields
Checkpoint @ $902A A:$A0, X:$04, Y:$00, Z:$00, P:$B5 : drce_not_eof CHECK<1/3>
Checkpoint @ $904F A:$0D, X:$04, Y:$00, Z:$00, P:$35 : drce_not_eof CHECK<2/3>
Checkpoint @ $9077 A:$42, X:$04, Y:$00, Z:$00, P:$35 : drce_not_eof CHECK<3/3>
Checkpoint @ $90B5 A:$62, X:$44, Y:$30, Z:$00, P:$34 :LFN(0D): bit03161352_m?rge-_550ca13?.bi
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8C3F A:$02, X:$30, Y:$30, Z:$00, P:$37 :-
Checkpoint @ $8C67 A:$30, X:$30, Y:$30, Z:$00, P:$34 :dos_readdir[00A0]==========================================
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $ACA7 A:$30, X:$30, Y:$30, Z:$00, P:$34 :FileDesc<=00,80,02,00,00,00,02,00 - 00,00,00,A0,00,00,00,00
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8D1D A:$32, X:$0B, Y:$34, Z:$00, P:$34 : (8.3)+(ATTRIB)+(NAME[0]) = BOOTLOGOM65 20 42
Checkpoint @ $8F30 A:$00, X:$0B, Y:$20, Z:$00, P:$37 : processing SHORT-name
Checkpoint @ $8FDC A:$20, X:$04, Y:$0B, Z:$03, P:$35 : drce_fl populated fields
Checkpoint @ $902A A:$C0, X:$04, Y:$00, Z:$03, P:$B5 : drce_not_eof CHECK<1/3>
Checkpoint @ $904F A:$0C, X:$04, Y:$00, Z:$03, P:$35 : drce_not_eof CHECK<2/3>
Checkpoint @ $9077 A:$42, X:$04, Y:$00, Z:$03, P:$35 : drce_not_eof CHECK<3/3>
Checkpoint @ $90B5 A:$42, X:$43, Y:$30, Z:$03, P:$34 :LFN(0C): BOOTLOGO.M65??????????????????
Checkpoint @ $9135 A:$4F, X:$00, Y:$30, Z:$03, P:$37 :Found the file...
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=005E8800.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=005E8A00.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=005E8C00.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=005E8E00.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=005E9000.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=005E9200.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=005E9400.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=005E9600.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00147E00.
Checkpoint @ $92FC A:$0F, X:$AC, Y:$0A, Z:$04, P:$37 :WARN: PRINTHEX in dfanc_check
Checkpoint @ $9B75 A:$00, X:$8A, Y:$0A, Z:$00, P:$37 :  try-loading KICKUP
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8C3F A:$02, X:$30, Y:$30, Z:$00, P:$37 :-
Checkpoint @ $8C67 A:$30, X:$30, Y:$30, Z:$00, P:$34 :dos_readdir[0000]==========================================
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $ACA7 A:$30, X:$30, Y:$30, Z:$00, P:$34 :FileDesc<=00,80,02,00,00,00,02,00 - 00,00,00,00,00,00,00,00
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8D1D A:$43, X:$0B, Y:$34, Z:$00, P:$34 : (8.3)+(ATTRIB)+(NAME[0]) = LOUD        08 4C
Checkpoint @ $8DB6 A:$00, X:$0B, Y:$08, Z:$00, P:$37 : is Volume ID, so skip this record
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00240800.
Checkpoint @ $8C3F A:$02, X:$30, Y:$30, Z:$00, P:$37 :-
.
.
.

Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D3200.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D3400.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D3600.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00148200.
Checkpoint @ $92FC A:$00, X:$54, Y:$1A, Z:$04, P:$37 :WARN: PRINTHEX in dfanc_check
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D3800.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D3A00.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D3C00.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D3E00.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D4000.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D4200.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D4400.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=006D4600.
Checkpoint @ $AD18 A:$30, X:$30, Y:$30, Z:$00, P:$34 :sd_sector: $d681=00148200.
Checkpoint @ $92FC A:$0F, X:$58, Y:$1A, Z:$04, P:$37 :WARN: PRINTHEX in dfanc_check
Checkpoint @ $9E1D A:$03, X:$CF, Y:$00, Z:$3F, P:$35 :  OK-loading CHARROM
Checkpoint @ $9E61 A:$00, X:$00, Y:$19, Z:$00, P:$37 :  OK-loading MEGA65-ROM
Checkpoint @ $9E7D A:$00, X:$00, Y:$19, Z:$00, P:$35 :JUMPing into ROM-code

```  
release SW-15 by pushing it DOWN/OFF,  
-> boot-screen should disappear and c65 mode presented.  

* RUN-STOP and RESTORE
press and hold the CBM/RUNSTOP key (on USB-KB this is the ESC key),
-> with ESC key pressed, the cursor will flash fast,
with ESC pressed, tap CBM/RESTORE (on USB-KB this is the PG-UP key).
-> the screen will clear,  
-> the colors of the background and border will return to their default values,
-> cursor will go to the top-left, with a ```READY.``` prompt.
release the ESC key.

* RESET with RUNSTOP and RESTORE
press and hold the CBM/RUNSTOP key (on USB-KB this is the ESC key),
-> with ESC key pressed, the cursor will flash fast,
with ESC pressed, press and hold CBM/RESTORE for at least 1-second,
-> the machine will reboot,  
release the ESC key.

The End.
