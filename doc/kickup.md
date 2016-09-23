## This is the 'kickup' documentation file.

# Table of Contents:

[Introduction](#introduction)  
[Setup on the PC](#setup-on-the-pc)  
[How to use](#how-to-use)  
[Breakpoint](#breakpoint)  

## Introduction

The Serial Mo
,.,.,.,,,.,

ce00-ceff
 possibly scratch space


8000
 trap_entry_points

81f8
 relocated cpu vectors
81ff

8200
 hypervisor trap entry points
  nosuchtrap
  return_from_trap_with_success
  return_from_trap_with_failure
  invalid_subfunction

.include _dos, _mem, _task

  reset_machine_state
  reset_entry_allow_etherkick
  reset_entry_no_etherkick
  reset_entry_common (main execution thread upon startup)
normalboot
tryreadmbr
gotmbr
mountsystemdiskok
logook
kickuproutine
postkickup
findrom
loadrom
loadedcharromok
loadc65rom
loadedok
jmp go64

;	========================
subroutines
;	========================

romfiletoolong
romfiletooshort
fileopenerror
sdcarderror

toupper

readmbr
sdreset
sd_resetsequence
sdtimeoutreset
sdreadytest
sd_map_sectorbuffer
sd_unmap_sectorbuffer
sd_readsector
redoread

printsectoraddress
sd_inc_fixedsectornumber
sdhc1
sd_fix_sectornumber
sdcardmode

checkromok
storeromsum
mapromchecksumrecord
calcromsum

resetdisplay
resetpalette
erasescreen
erasescreendmalist
copydiskchooserdmalist

printmessage
printbanner
printhex

go64

resetmemmap
enhanced_io
keyboardread
default_rom

setupethernet
checkethernet
gotpacket
notarp

debug_wait_for_switch_toggle

hypervisor_nmi
hypervisor_irq
hypervisor_setup_copy_region
checkpoint
endofcheckpointmessage
checkpoint_bytetohex

;	========================
text & strings (non-executable)
;	========================

msg_checkpoint_eom
msg_*

;	========================

diskchooserstart
diskchooserend

bb00
dos_disk_table

bc00
kickstart_scratchbyte0
dos_disk_count
dos_default_disk
dos_disk_current_disk
dos_disk_table_offset
dos_disk_cwd_cluster
dos_dirent_longfilename
dos_dirent_cluster
dos_requested_filename
dos_current_sector_in_cluster

dos_file_descriptors
dos_current_file_descriptor

bd00
.include "kickstart_process_descriptor.a65"

be00
Kickstart stack (8-bit)

bf00
Kickstart ZP at $BF00-$BFFF
 kickstart_boot_flags
 dos_scratch_vector
 hypervisor_userspace_copy_vector
 zptempv
 zptempv32
 dos_file_loadaddress
 checkpoint_a
 checkpoint_pch
 sdcounter

c000




The End.


