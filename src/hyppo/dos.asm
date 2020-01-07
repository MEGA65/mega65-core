/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */

        // XXX - Track down why 2nd and subsequent LFN blocks are not used.

dos_and_process_trap:

        // XXX - Machine is being updated to automatically disable IRQs on trapping
        // to hypervisor, but for now, we need to do this explicitly.
        // Should be able to be removed after 20160103
        // BG: cannot confirm removal of the instruction below. Dated 20160902
        sei

        // XXX - We have just added a fix for this in the CPU, to CLEAR DECIMAL MODE
        // on entry to the hypervisor. But I'm not taking any chances just now.
        //
        cld

        // Sub-function is selected by A.
        // Bits 6-1 are the only ones used.
        // Mask out bit 0 so that indirect jmp's are valid.
        //
        and #$FE
        tax
        jmp_zp_x(dos_and_process_trap_table)

//         ========================

dos_and_process_trap_table:

        // $00 - $0E
        //
        .word trap_dos_getversion
        .word trap_dos_getdefaultdrive
        .word trap_dos_getcurrentdrive          // appears out-of-order (is far below)
        .word trap_dos_selectdrive
        .word trap_dos_getdisksize              // not currently implememted
        .word trap_dos_getcwd                   // not currently implememted
        .word trap_dos_chdir                    // not currently implememted
        .word trap_dos_mkdir                    // not currently implememted

        // $10 - $1E
        //
        .word trap_dos_rmdir                    // not currently implememted
        .word trap_dos_opendir
        .word trap_dos_readdir
        .word trap_dos_closedir
        .word trap_dos_openfile
        .word trap_dos_readfile                 
        .word trap_dos_writefile                // not currently implememted
        .word trap_dos_mkfile                   // implementation started

        // $20 - $2E
        //
        .word trap_dos_closefile
        .word trap_dos_closeall
        .word trap_dos_seekfile                 // not currently implememted
        .word trap_dos_rmfile                   // not currently implememted
        .word trap_dos_fstat                    // not currently implememted
        .word trap_dos_rename                   // not currently implememted
        .word trap_dos_filedate                 // not currently implememted
        .word trap_dos_setname

        // $30 - $3E
        //
        .word trap_dos_findfirst
        .word trap_dos_findnext
        .word trap_dos_findfile
        .word trap_dos_loadfile
        .word trap_dos_geterrorcode
        .word trap_dos_setup_transfer_area
        .word invalid_subfunction
        .word invalid_subfunction

        // $40 - $4E
        //
        .word trap_dos_d81attach0
        .word trap_dos_d81detach
        .word trap_dos_d81write_en
        .word trap_dos_d81attach1
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $50 - $5E
        //
        .word trap_dos_gettasklist              // not currently implememted
        .word trap_dos_sendmessage              // not currently implememted
        .word trap_dos_receivemessage           // not currently implememted
        .word trap_dos_writeintotask            // not currently implememted
        .word trap_dos_readoutoftask            // not currently implememted
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $60 - $6E
        //
        .word trap_dos_terminateothertask       // not currently implememted
        .word trap_dos_create_task_native       // not currently implememted
        .word trap_dos_load_into_task           // not currently implememted
        .word trap_dos_create_task_c64          // not currently implememted
        .word trap_dos_create_task_c65          // not currently implememted
        .word trap_dos_exit_and_switch_to_task  // not currently implememted
        .word trap_dos_switch_to_task           // not currently implememted
        .word trap_dos_exit_task                // not currently implememted

        // $70 - $7E
        //
        .word trap_task_toggle_rom_writeprotect
        .word trap_task_toggle_force_4502
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word trap_serial_monitor_write
        .word reset_entry

trap_serial_monitor_write:
        sty hypervisor_write_char_to_serial_monitor
        jmp return_from_trap_with_success

//         ========================

trap_task_toggle_force_4502:
        lda hypervisor_feature_enables
        eor #$20
        sta hypervisor_feature_enables
        jmp @returnFeatureState

trap_task_toggle_rom_writeprotect:
        lda hypervisor_feature_enables
        eor #$04
        sta hypervisor_feature_enables
@returnFeatureState:
        // Pass updated state back out to caller, so they know the result
        sta hypervisor_a
        jmp return_from_trap_with_success

trap_dos_getversion:

        // Return OS and DOS version.
        // A/X = OS Version major/minor
        // Z/Y = DOS Version major/minor

        lda #<os_version
        sta hypervisor_x
        lda #>os_version
        sta hypervisor_a
        lda #<dos_version
        sta hypervisor_z
        lda #>dos_version
        sta hypervisor_y
        jmp return_from_trap_with_success

//         ========================

trap_dos_getdefaultdrive:

        lda dos_default_disk
        sta hypervisor_a
        jmp return_from_trap_with_success

//         ========================

trap_dos_selectdrive:

        jsr dos_set_current_disk

return_from_trap_with_carry_flag:
        bcs !+
        jmp return_from_trap_with_failure
!:      jmp return_from_trap_with_success

trap_dos_closeall:

        jsr dos_clear_filedescriptors
        jmp return_from_trap_with_success

//         ========================

trap_dos_loadfile:

        // Only allow loading into lower 16MB to avoid possibility of writing
        // over hypervisor
        //
        lda hypervisor_x
        sta <dos_file_loadaddress
        lda hypervisor_y
        sta <dos_file_loadaddress+1
        lda hypervisor_z
        sta <dos_file_loadaddress+2
        lda #$00
        sta <dos_file_loadaddress+3

        jsr dos_readfileintomemory
        jmp return_from_trap_with_carry_flag

//         ========================

trap_dos_setup_transfer_area:

        jsr hypervisor_setup_copy_region

        jmp return_from_trap_with_carry_flag

trap_dos_setname:

        // read file name from any where in bottom 32KB of RAM, as mapped on entry
        // to the hypervisor (this prevents the user from setting the filename to some
        // piece of the hypervisor, and thus leaking hypervisor data to user-land if the
        // user were to later query the filename).

        Checkpoint("trap_dos_setname")

        jsr hypervisor_setup_copy_region
        bcc tdsnfailure

        ldx <hypervisor_userspace_copy_vector
        ldy 1+<hypervisor_userspace_copy_vector
        jsr dos_setname
        bcc tdsnfailure

        // setname succeeded
        //

        jmp return_from_trap_with_success

//         ========================

tdsnfailure:
        lda dos_error_code
        jmp return_from_trap_with_failure

//         ========================


illegalvalue:

        // BG: the below section seems never called from anywhere: suggest removal

//         tya
//         tax
//         jsr checkpoint_bytetohex
//         sty iv1+0
//         stx iv1+1
//
//         jsr checkpoint
//         .byte 0,"Filename contains $00 @ position $"
// iv1:        .byte "%%",0

        lda #dos_errorcode_illegal_value
        sta dos_error_code
        jmp return_from_trap_with_failure

//         ========================

trap_dos_getcurrentdrive:

        lda dos_disk_current_disk
        sta hypervisor_a
        jmp return_from_trap_with_success

//         ========================

trap_dos_mkfile:

	// XXX Filename must already be set.
	// XXX Must be a file in the current directory only.
	// XXX Can only create normal files, not directories
	//     (change attribute after).
	// XXX Only supports 8.3 names for now.
	// XXX Allocates 512KB at a time, i.e., a full FAT sector's
	//     worth of clusters.
	// XXX Allocates a contiguous block, so that D81s etc can
	//     be created, and guaranteed contiguous on the storage,
	//     so that they can be mounted.
	// XXX Size of file specified in $ZZYYXX, i.e., limit of 16MB.

	// First, make sure the file doesn't already exist
	jsr dos_findfile
	bcc !+
	// File exists, so abort
	clc
	lda #dos_errorcode_file_exists
	sta dos_error_code
	jmp return_from_trap_with_failure
!:

	// We need 1 FAT sector per 512KB of data.
	// I.e., shift ZZ right by three bits to get number
	// of empty FAT sectors we need to indicate sufficient space.
	lda hypervisor_z
	lsr
	lsr
	lsr
	clc
	adc #$01 
	sta dos_scratch_byte_1
	sta $0715

	// Now go looking for empty FAT sectors
	// Start at cluster 2, and add 128 each time to step through
	// them.
	lda #$02
	sta zptempv32+0
	lda #$00
	sta zptempv32+1
	sta zptempv32+2
	sta zptempv32+3

	// Initially 0 empty pages found
	lda #0
	sta dos_scratch_byte_2

	jsr sd_map_sectorbuffer
	
find_empty_fat_page_loop:
	
	ldx #3
!:	lda zptempv32,x
	sta dos_current_cluster,x
	dex
	bpl !-

	jsr dos_cluster_to_fat_sector

	// Now read the sector
        ldx #3
!:      lda dos_current_cluster,x
        sta $d681,x
        dex
        bpl !-
	jsr sd_readsector

	// Is the page empty
	ldx #0
!:	lda $de00,x
	bne !+
	lda $df00,x
	bne !+

	inx
	bne !-
!:
	
	// Z=1 if FAT sector all unallocated, Z=0 otherwise
	beq fat_sector_is_empty

	// Reset empty FAT sector counter
	lda #0
	sta dos_scratch_byte_2
	jmp !+
	
fat_sector_is_empty:	
	inc dos_scratch_byte_2
	lda dos_scratch_byte_2
	cmp dos_scratch_byte_1
	beq found_enough_contiguous_free_space
!:
	// Need to find another
	lda #$80
	clc
	adc zptempv32+0
	sta zptempv32+0
	lda zptempv32+1
	adc #0
	sta zptempv32+1
	lda zptempv32+2
	adc #0
	sta zptempv32+2
	lda zptempv32+3
	adc #0
	sta zptempv32+3

	// XXX Check that we haven't hit the end of the file system
	
	jmp find_empty_fat_page_loop

found_enough_contiguous_free_space:

	inc $0716
	
	// Space begins dos_scratch_byte_2 FAT sectors before here,
	// so rewind back to there by taking $80 away for each count.
	dec dos_scratch_byte_2
	
!:	lda dos_scratch_byte_2
	beq !+
	lda zptempv32+0
	sec
	sbc #$80
	sta zptempv32+0
	lda zptempv32+1
	sbc #0
	sta zptempv32+1
	lda zptempv32+2
	sbc #0
	sta zptempv32+2
	lda zptempv32+3
	sbc #0
	sta zptempv32+3
	dec dos_scratch_byte_2
	jmp !-
!:
	// zptempv32 now contains the starting cluster for our file

	// Find directory entry slot
	jsr dos_find_free_dirent
	bcs !+
	// Couldn't find a free dirent, so return whatever error
	// we have been indicated.
	rts
!:

	// Show offset in directory sector for dirent
	lda dos_scratch_vector+0
	sta $0700
	lda dos_scratch_vector+1
	and #$01
	sta $0701

	// Show directory sector
	ldx #3
!:	lda $d681,x
	sta $0703,x
	dex
	bpl !-

	// Show first cluster we will use
	ldx #3
!:	lda zptempv32,x
	sta $0708,x
	dex
	bpl !-
	
	// XXX Populate dirent structure
	// dirent: erase old contents
	ldy #31
	lda #0
!:	sta (dos_scratch_vector),y
	dey
	bpl !-
	// dirent: filename
	ldy #fs_fat32_dirent_offset_shortname
!:	lda dos_requested_filename,y
	sta (dos_scratch_vector),y
	beq !+
	iny
	cpy #11
	bne !-
!:
	
	// dirent: attributes
	ldy #fs_fat32_dirent_offset_attributes
	lda #$20 // Archive bit set
	sta (dos_scratch_vector),y
	// dirent: start cluster
	ldy #fs_fat32_dirent_offset_clusters_low
	lda zptempv32+0
	sta (dos_scratch_vector),y
	iny
	lda zptempv32+1
	sta (dos_scratch_vector),y
	ldy #fs_fat32_dirent_offset_clusters_high
	lda zptempv32+2
	sta (dos_scratch_vector),y
	iny
	lda zptempv32+3
	sta (dos_scratch_vector),y	
	// dirent: file length
	ldy #fs_fat32_dirent_offset_file_length
	lda hypervisor_x
	sta (dos_scratch_vector),y
	iny
	lda hypervisor_y
	sta (dos_scratch_vector),y
	iny
	lda hypervisor_z
	sta (dos_scratch_vector),y
	iny
	lda #0
	sta (dos_scratch_vector),y
	
	
	// XXX Update both FATs to make the allocation
	
	jmp return_from_trap_with_failure

dos_find_free_dirent:
	// Start by opening the directory.
	jsr dos_opendir
	// Then look for free directory entry slots.
	jsr sd_map_sectorbuffer
	
empty_dirent_search_loop:	
	
	jsr dos_file_read_current_sector

	// Look for free dirent in first half of each sector.
	ldx #0
	lda #$de
	sta dos_scratch_vector+1
!:	lda $de00,x
	cmp #$00 // vacant
	beq available_dirent_slot
	cmp #$e5 // deleted
	beq available_dirent_slot
	txa
	adc #$20
	tax
	bne !-
	inc dos_scratch_vector+1
!:	lda $de00,x
	cmp #$00 // vacant
	beq available_dirent_slot
	cmp #$e5 // deleted
	beq available_dirent_slot
	txa
	adc #$20
	tax
	bne !-

	// No empty slots in this directory, so see if there any more sectors in
	// this directory?
	jsr dos_file_advance_to_next_sector
	bcs empty_dirent_search_loop

	// Directory is full, so return error
	// XXX Later we should allow extending the directory by adding another cluster.
	lda #dos_errorcode_directory_full
	sta dos_error_code
	clc
	rts
	
available_dirent_slot:	
	stx dos_scratch_vector+0
	
	sec
	rts
//         ========================
	
trap_dos_opendir:

        // X = File descriptor
        // Y = Page of memory to write dirent into

        // Open the current working directory for iteration.
        //
        jsr dos_opendir
        bcs tdod1

        // Something has gone wrong. Assume dos_opendir will
        // have set error code
        //
        lda dos_error_code
        jmp return_from_trap_with_failure

tdod1:
        // Directory opened ok.
        //
        lda dos_current_file_descriptor
        sta hypervisor_a
        jmp return_from_trap_with_success

//         ========================

trap_dos_readdir:

        // Read next directory entry from file descriptor $XX
        // Return dirent structure to $YY00
        // in first 32KB of mapped address space

        Checkpoint("trap_dos_readdir")

        jsr sd_map_sectorbuffer

        // Get offset to current file descriptor
        // (we can't use X register, as has been clobbered in the jump
        // table dispatch code)
        //
        ldx hypervisor_x
        stx dos_current_file_descriptor

        jsr dos_get_file_descriptor_offset
        bcc tdrd1
        sta dos_current_file_descriptor_offset

        jsr dos_readdir
        bcc tdrd1

        // Read the directory entry, now copy it to userland
        //
        jsr hypervisor_setup_copy_region
        bcc tdrd1

        // We can now copy the bytes of the dirent to user-space
        //
        ldy #dos_dirent_structure_length-1
tdrd2:
        // This loop actually copies the whole dirent.
        // XXX dos_dirent_longfilename must be first in the dirent structure
        lda dos_dirent_longfilename,y
        sta (<hypervisor_userspace_copy_vector),y
        dey
        bpl tdrd2

        Checkpoint("trap_dos_readdir <success>")

        jmp return_from_trap_with_success

//         ========================

tdrd1:
        Checkpoint("trap_dos_readdir <failure>")

        lda dos_error_code
        jmp return_from_trap_with_failure

//         ========================

trap_dos_closedir:
        jmp trap_dos_closefile

//         ========================

trap_dos_readfile:
	jsr dos_readfile	
        jmp return_from_trap_with_carry_flag
	
trap_dos_openfile:

        // Opens file in current dirent structure
        // XXX - This means we must preserve the dirent struct when
        // context-switching to avoid a race-condition

        jsr dos_openfile
        bcc tdof1

        Checkpoint("trap_dos_openfile <success>")

        jmp return_from_trap_with_success

tdof1:
        Checkpoint("trap_dos_openfile <failure>")

        lda dos_error_code
        jmp return_from_trap_with_failure

//         ========================

trap_dos_closefile:

        ldx hypervisor_x
        stx dos_current_file_descriptor

        jsr dos_get_file_descriptor_offset
        bcc tdcf1
        jsr dos_closefile
        bcc tdcf1

        Checkpoint("trap_dos_closefile <success>")

        jmp return_from_trap_with_success
tdcf1:
        Checkpoint("trap_dos_closefile <failure>")

        lda dos_error_code
        jmp return_from_trap_with_failure

//         ========================

trap_dos_findfile:

        jsr dos_findfile
        jmp return_from_trap_with_carry_flag

//         ========================

trap_dos_findfirst:

        jsr dos_findfirst
        jmp return_from_trap_with_carry_flag

//         ========================

trap_dos_findnext:

        jsr dos_findnext
        jmp return_from_trap_with_carry_flag

//         ========================

trap_dos_geterrorcode:

        lda dos_error_code
        sta hypervisor_a

        tax                                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty tdgec1+0
        stx tdgec1+1

        jsr checkpoint
        .byte 0
        ascii("dos_geterrorcode <=$")
tdgec1: ascii("%%>")
        .byte 0

        jmp return_from_trap_with_success

//         ========================

trap_dos_d81attach0:

        Checkpoint("trap_dos_d81attach0")

        jsr dos_d81attach0
        jmp return_from_trap_with_carry_flag

//         ========================

trap_dos_d81attach1:

        Checkpoint("trap_dos_d81attach1")

        jsr dos_d81attach1
        jmp return_from_trap_with_carry_flag

//         ========================

trap_dos_d81detach:

        jsr dos_d81detach

        jmp return_from_trap_with_success

//         ========================

trap_dos_d81write_en:

        jsr dos_d81write_en
        jmp return_from_trap_with_carry_flag

dos_d81write_en:
        lda $d68b
        and #$03
        cmp #$03
        bne td81we1
        ora #$04
        sta $d68b

        // Mark disk image write-enabled in proces descriptor
        lda currenttask_d81_image0_flags
        ora #d81_image_flag_write_en

        sec
        rts

td81we1:
        // No disk image mounted
        //

        Checkpoint("dos_d81writ_en-FAIL")

        lda #dos_errorcode_no_such_disk
        sta dos_error_code
        clc
        rts

//         ========================

// BG: the following are placeholders for the future development

trap_dos_getdisksize:
trap_dos_getcwd:
trap_dos_chdir:
trap_dos_mkdir:
trap_dos_rmdir:
trap_dos_writefile:
trap_dos_seekfile:
trap_dos_rmfile:
trap_dos_fstat:
trap_dos_rename:
trap_dos_filedate:
trap_dos_gettasklist:
trap_dos_sendmessage:
trap_dos_receivemessage:
trap_dos_writeintotask:
trap_dos_readoutoftask:
trap_dos_terminateothertask:
trap_dos_create_task_native:
trap_dos_load_into_task:
trap_dos_create_task_c64:
trap_dos_create_task_c65:
trap_dos_exit_and_switch_to_task:
trap_dos_switch_to_task:
trap_dos_exit_task:

        jmp invalid_subfunction//

//         ========================

// ======================================================================================
// ======================================================================================
// ======================================================================================

// Clear all file descriptors.
// This just consists of setting the drive number to $ff,
// which indicates "no such drive"
// Drive number field is first byte of file descriptor for convenience

dos_clear_filedescriptors:

        // XXX - This doesn't close the underlying file descriptors!
        //
        lda #$ff
        sta currenttask_filedescriptor0
        sta currenttask_filedescriptor1
        sta currenttask_filedescriptor2
        sta currenttask_filedescriptor3
        sec
        rts

//         ========================

// Read partition table from SD card.
//
// Add all FAT32 partitions to our list of known disks.
//
// This routine assumes that the SD card has been reset and is ready to
// service requests.
//
// XXX - We don't support extended partition tables! Only the old-fashion
// 4 DOS partitions.  We might get excited and add support for them later
//
dos_read_partitiontable:

        // clear error code
        //
        lda #0
        sta dos_error_code

        // Clear the list of known disks
        //
        jsr dos_initialise_disklist

        jsr dos_read_mbr
        bcc l_drpt_fail

        // Make the sector buffer visible
        //
        jsr sd_map_sectorbuffer

        lda #dos_errorcode_bad_signature
        sta dos_error_code

        // check for $55, $AA MBR signature
        //
        lda [sd_sectorbuffer+$1FE]
        cmp #$55
        bne l_drpt_fail
        lda [sd_sectorbuffer+$1FF]
        cmp #$AA
        bne l_drpt_fail

        // yes, $55AA MBR signature was found

        Checkpoint("Found $55, $AA at $1FE on MBR")

        // Partitions start at offsets $1BE, $1CE, $1DE, $1EE
        // so consider each in turn.  Opening the partition causes other sectors to
        // be read, so we must re-read the MBR between each

        // get pointer to second half of sector buffer so that we can access the
        // partition entries as we see fit.
        //

        lda #<[sd_sectorbuffer+$1BE]
        sta dos_scratch_vector
        lda #>[sd_sectorbuffer+$1BE]
        sta dos_scratch_vector+1
        Checkpoint("=== Checking Partition #1 at $01BE")
        jsr dos_consider_partition_entry

        jsr dos_read_mbr
        bcc l_drpt_fail
        lda #<[sd_sectorbuffer+$1CE]
        sta dos_scratch_vector
        Checkpoint("=== Checking Partition #2 at $01CE")
        jsr dos_consider_partition_entry

        jsr dos_read_mbr
        bcc l_drpt_fail
        lda #<[sd_sectorbuffer+$1DE]
        sta dos_scratch_vector
        Checkpoint("=== Checking Partition #3 at $01DE")
        jsr dos_consider_partition_entry

        jsr dos_read_mbr
        bcs !+
l_drpt_fail:
        jmp drpt_fail
!:      lda #<[sd_sectorbuffer+$1EE]
        sta dos_scratch_vector
        Checkpoint("=== Checking Partition #4 at $01EE")
        jsr dos_consider_partition_entry

        lda #0
        sta dos_error_code
        sec
        rts

//         ========================

dos_read_mbr:

        // Offset zero on disk
        //

        lda #0
        sta sd_address_byte0
        sta sd_address_byte1
        sta sd_address_byte2
        sta sd_address_byte3

        Checkpoint("Reading MBR @ 0x00000000")

        // Read sector
        //
        jsr sd_readsector
        bcs !+
        jmp drpt_fail
!:      rts

//         ========================

dos_initialise_disklist:

        lda #0
        sta dos_disk_count
        rts

//         ========================

dos_consider_partition_entry:

        lda #$00
        sta dos_error_code

        // Offset within partition table entry of partition type
        //
        // BG: make this a hash-define
        //
        ldy #$04

        // Get partition type byte
        //
        lda (<dos_scratch_vector),y

        // We like FAT32 partitions, whether LBA or CHS addressed, although we actually
        // use LBA addressing.  XXX - Can this cause problems for CHS partitions?
        // (SD cards which must really use LBA, can still show up with CHS partitions!
        //  this is really annoying.)
        //
        cmp #constant_partition_type_fat32_lba        // compare with 0x0C
        beq partitionisinteresting_lba

        cmp #constant_partition_type_fat32_chs        // compare with 0x0B
        beq partitionisinteresting_chs

        cmp #constant_partition_type_megea65_sys // compare with 0x41
        beq partitionisinteresting_mega65sys

        lda #dos_errorcode_partition_not_interesting
        sta dos_error_code
        jmp partitionisnotinteresting

//         ========================

partitionisinteresting_mega65sys:

        Checkpoint("MEGA65 System Partition (type=0x41)")

        // Only one system partition
        lda syspart_present
        beq !+
        jmp partitionerror
!:
        // Store start and length of System partition
        // (These are the first two fields of the syspart structure
        //  to facilitate a simple copy here)
        ldy #$08
        ldx #$00

spc1:   lda (<dos_scratch_vector),y
        sta syspart_structure,x
        inx
        iny
        cpy #$10
        bne spc1

        jsr syspart_open
        sec
        rts

partitionisinteresting_lba:

        Checkpoint("Partn has fat32_lba (type=0x0c)")

        jmp partitionisinteresting

partitionisinteresting_chs:

        Checkpoint("WARN:Partn has fat32_chs (type=0x0b)")

        jmp partitionisinteresting

//         ========================

partitionisinteresting:

        // Make sure we have a spare disk slot
        lda dos_disk_count
        cmp #dos_max_disks
        bne !+
        jmp partitionerror
!:
        // Partition is FAT32 (either 0B or 0C), so add it to the list

        // Disk structures in dos_disk_table are 32 bytes long, so shift count left
        // 5 times to get offset in dos disk list table
        //
        // initially, dos_disk_count=00 so shifting results in =00
        //
        lda dos_disk_count
        asl
        asl
        asl
        asl
        asl
        tax

        // Copy relevant fields into place
        // These are start of partition and length of partition (both in sectors)
        // XXX - This requires that our dos_disk_table has these two fields together
        // at the start of the structure.
        //
        ldy #$08        // partition_lba_begin (4 bytes)

dcpe1:  lda (<dos_scratch_vector),y
        sta dos_disk_table,x
        inx
        iny
        cpy #$10        // partition_num_sectors (4 bytes)
        bne dcpe1

        // Examine the internals of the partition to get the remaining fields.
        // At this point we no longer use the contents of the MBR
        //

        jsr dos_disk_openpartition
        bcc partitionerror

        jsr dump_disk_table

        // Check if partition is bootable (or the only partition)
        // If so, make the partition the default disk
        //
        // BG, we should examine all four partitions before setting the default disk
        //
        lda dos_disk_count
        beq makethispartitionthedefault
        ldy #$00
        lda (<dos_scratch_vector),y
        bpl dontmakethispartitionthedefault


makethispartitionthedefault:
        lda dos_disk_count
        sta dos_default_disk

        // print out this message to Checkpoint
        //

        tax                                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty mtptd
        stx mtptd+1

        jsr checkpoint
        .byte 0
        ascii("dos_default_disk = ")
mtptd:  ascii("xx")
        .byte 0

// jsr dump_disk_table

        // return OK
        //
        sec
        rts

//         ========================

dontmakethispartitionthedefault:

        ldx dos_disk_count

        // print out this message to Checkpoint
        //

                                        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx mtptd2

        jsr checkpoint
        .byte 0
        ascii("Part#")
mtptd2: ascii("x NOT set to the default_disk")
        .byte 0

// jsr dump_disk_table

        // return OK
        //

        sec
        rts

//         ========================

partitionisnotinteresting:

        // return OK
        //

        Checkpoint("Partition not interesting")

        sec
        rts

//         ========================

drpt_fail:

        // error code will already be set

partitionerror:

        // return ERROR

        ldx dos_error_code                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty perr
        stx perr+1

        jsr checkpoint
        .byte 0
        ascii("partitionerror=")
perr:   ascii("xx")
        .byte 0

        clc
        rts

dos_disk_openpartition:

        Checkpoint("dos_disk_openpartition: (examine Vol ID)")

        // A contains the disk number we are trying to open.
        //
        lda #$00
        sta dos_error_code

        // Load first sector of file system and parse.
        // This is the Volume ID pointed to by the PartitionTable in the MBR

        // Get offset of disk entry in our disk table structure
        //
        lda dos_disk_count
        asl
        asl
        asl
        asl
        asl
        sta dos_disk_table_offset

        // Now pull the start sector from the structure and get ready to request
        // that structure from the SD card.
        //
        ora #fs_start_sector        // OR with 00 does nothing, but this is the standard
        tay
        ldx #$00

ddop1:  lda dos_disk_table,y
        sta sd_address_byte0,x
        iny
        inx
        cpx #$04
        bne ddop1

jsr dumpsectoraddress        // debugging

        jsr sd_readsector
        bcc partitionerror

        // We now have the sector, so parse.

        jsr sd_map_sectorbuffer

//         ========================

        // Check for 55/AA singature (again, for the Vol-ID of this partition)
        //

        lda #dos_errorcode_bad_signature
        sta dos_error_code

        lda [sd_sectorbuffer+$1FE]
        cmp #$55
        beq ddop1a
        jmp partitionerror
ddop1a:
        lda [sd_sectorbuffer+$1FF]
        cmp #$AA
        beq ddop1b
        jmp partitionerror
ddop1b:
        Checkpoint("Partn has $55, $AA GOOD")

        // Start populating fields

//         BG assumes this is all correct...

//         ========================

        // Filter out obviously FAT16/FAT12 file systems
        //
        lda #dos_errorcode_is_small_fat
        sta dos_error_code
        //
        // BG i think we dont need to check this for minimal operation
        //
        // for fat32, the 11'th entry is unused, http://www.easeus.com/resource/fat32-disk-structure.htm
        //
        lda [sd_sectorbuffer+$11]        // this is NOT the MBSyte of the number of FATs
        bne partitionerror

//         ========================

        // get # copies of fat
        //
        lda dos_disk_table_offset
        ora #fs_fat32_fat_copies        // is $17
        tay
        lda [sd_sectorbuffer+$10]        // should be 2
        sta dos_disk_table,y

//         ========================

        // With root directory entries = 0, the reserved sector count
        // is the number of reserved sectors, plus (copies of fat) *
        // (sectors in one copy of the fat).
        // the first FAT begins immediately after the reserved sectors

        // Determine system sector count
        // (= reserved sectors + fat_count * fat_sectors)
        // $20 + $EE5 + $EE5 = $1DEA
        // plus partition offset = $81 = $1E6B
        // partition length = $3BAF7F
        // $08 sectors / cluster
        // so data sectors in partition = $3BAF7F - $1DEA = $3B9195
        // = $77232 clusters

        // BG does not like the above reasoning, ie fixed number of reserved sectors.

        // Reserved sector field on disk is only 2 bytes!
        //
        lda dos_disk_table_offset
        ora #fs_fat32_system_sectors        // is $0D
        tay
        ldx #$00

ddop10: lda [sd_sectorbuffer+$0E],x
        sta dos_disk_table,y
        iny
        inx
        cpx #$02
        bne ddop10

//         ========================

        // Store length of one copy of the FAT
        //
        lda dos_disk_table_offset
        ora #fs_fat32_length_of_fat        // is $09
        tay
        ldx #$00

ddop11: lda [sd_sectorbuffer+$24],x        // sectors_per_fat
        sta dos_disk_table,y
        iny
        inx
        cpx #$04
        bne ddop11

//         ========================

        // Get number of reserved clusters.  We only allow upto 255 reserved
        // clusters, so report an error if the upper three bytes are not zero
        //
        // BG: why only 255 reserved clusters? and isnt it reserved sectors instead?
        // and seems to be looking at the root_dir_first_cluster
        //
        lda #dos_errorcode_too_many_reserved_clusters
        sta dos_error_code

        lda [sd_sectorbuffer+$2C+1]
        ora [sd_sectorbuffer+$2C+2]
        ora [sd_sectorbuffer+$2C+3]

        // XXX - 16 bit BNE should be fine here! Why doesn't it work?
        //         bne partitionerror

        beq ddop11ok
        jmp partitionerror

//         ========================

ddop11ok:

        // <64K reserved clusters, so file system passes this test -- just copy number
        //
        // BG does not agree with the logic, of <64k reservedclusters to passes
        // BG the code below could be changed to be same as lda,ora,tay
        //
        // BG, so by design, we reject any Vol_ID that has
        // RootDirFirstCluster[3..0] not equal to $00000002
        //
        ldy dos_disk_table_offset
        lda [sd_sectorbuffer+$2C]        // 2c is the ClusterNumberOfFirstRootDir
        sta [dos_disk_table + fs_fat32_reserved_clusters],y

// Checkpoint("dos_disk_table-1")
// jsr dump_disk_table        ; debugging

// dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00 = (fs_start_sector),                       (fs_sector_count)
// dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02 = type, (sectorsPerFat),(reservedSectors),(reservedClusters)
// dos_disk_table[10-17] = 00,00,00,00,00,00,00,02 = x..x                                ,(fs_fat32_fat_copies)
// dos_disk_table[18-1F] = 00,00,00,00,xx,xx,xx,xx

//         ========================

        // Now work out the sector of cluster 0, by adding:
        //   fs_fat32_system_sectors
        // + the length of each FAT
        // + start of partition,
        // and store this result in dos_disk_table[18..1B]
        //
        // For efficiency, we pull the fields we need out of the sector buffer,
        // instead of working out their offsets in the dos_disk_table structure.
        // BG disagree, we know the offsets of the fields in dos_disk_table

        // Start with fs_fat32_system_sectors (which is 16 bits), then pad MSBs with zero
        //
        lda dos_disk_table_offset
        ora #fs_fat32_system_sectors        // is $0D
        tay
        lda dos_disk_table_offset
        ora #fs_fat32_cluster0_sector        // is $18
        tax
        ldz #$02

ddop2:  lda dos_disk_table,y
        sta dos_disk_table,x
        iny
        inx
        dez
        bne ddop2

        // clear top 16 bits of cluster0_sector (dos_disk_table[1A,1B])
        //
        // BG: why tza, just do lda#$00
        tza
        sta [dos_disk_table+0],x
        sta [dos_disk_table+1],x

// Checkpoint("dos_disk_table-2")
// jsr dump_disk_table        ; debugging

// dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
// dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
// dos_disk_table[10-17] = 00,00,00,00,00,00,00,02
// dos_disk_table[18-1F] = 38,02,00,00,xx,xx,xx,xx -> $00000238


//         ========================

        // Now add length of fat for each copy of the fat
        //
        lda #dos_errorcode_not_two_fats
        sta dos_error_code

        // BG #FATs should be sourced from dos_disk_table[17], not from buffer+$10

        ldz [sd_sectorbuffer+$10]       // # of FAT copies
        beq l_partitionerror            // There must be at least one copy of the FAT!
        cpz #2
        beq ddop_addnextfatsectors
l_partitionerror:
        jmp partitionerror

ddop_addnextfatsectors:
        lda dos_disk_table_offset
        ora #fs_fat32_cluster0_sector   // is $18
        tay
        ldx #$00
        clc
        php                             // push processor-status (to remember the carry-flag)

ddop12: plp                             // pull processor-status
        lda dos_disk_table,y            // cluster0_sector
        adc [sd_sectorbuffer+$24],x     // sectors per fat ;BG should load from dos_disk_table[09]
        sta dos_disk_table,y            // cluster0_sector
        php
        iny
        inx
        cpx #$04
        bne ddop12

        plp
        //
        // as Z was initially 2 (#FATs), we do this loop twice
        // resulting in 2x the sectorsPerFat added to "reservedSectors".
        dez
        bne ddop_addnextfatsectors

// Checkpoint("dos_disk_table-3")
// jsr dump_disk_table        ; debugging

// dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
// dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
// dos_disk_table[10-17] = 00,00,00,00,00,00,00,02
// dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx -> $00000238 + ($000003e6 + $000003e6) = $00000A04

// BG does not agree with the calculations below, why do we need to calculate it this way?

        // Next, we temporarily need the number of data sectors, so that we can work
        // out the number of clusters in the file system.
        // This is the total number of sectors in the partition, minus the number of
        // reserved sectors.

        // Subtract (cluster 0 sector = 32 bits) from
        // (length of filesystem in sectors = 32 bits)

        lda dos_disk_table_offset
        ora #fs_fat32_cluster0_sector   // is $18
        tax
        lda dos_disk_table_offset
        ora #fs_fat32_cluster_count     // is $12
        tay
        sec
        lda [sd_sectorbuffer+$20+0]     // from FAT spec, this is number of sectors in partition
        sbc [dos_disk_table+0],x        // x=$18 initially
        sta [dos_disk_table+0],y        // y=$12 initially
        lda [sd_sectorbuffer+$20+1]
        sbc [dos_disk_table+1],x
        sta [dos_disk_table+1],y
        lda [sd_sectorbuffer+$20+2]
        sbc [dos_disk_table+2],x
        sta [dos_disk_table+2],y
        lda [sd_sectorbuffer+$20+3]
        sbc [dos_disk_table+3],x
        sta [dos_disk_table+3],y

//         ========================

get_sec_per_cluster:
        // Get sectors per cluster (and store in dos_disk_table entry)
        // (this gets destoryed below, so we have to re-read it again after)
        //
        lda dos_disk_table_offset
        ora #fs_fat32_sectors_per_cluster        // is $16
        tay
        lda [sd_sectorbuffer+$0D]
        sta dos_disk_table,y

// Checkpoint("dos_disk_table-4")
// jsr dump_disk_table        ; debugging

// dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
// dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
// dos_disk_table[10-17] = 00,00,FC,95,0F,00,08,02 -> new data appears
// dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx


//         ========================

        // Now divide number of sectors available for clusters by the number of
        // sectors per cluster to obtain the number of actual clusters in the file
        // system.  Since clusters must contain a power-of-two number of sectors,
        // we can implement the division using a simple shift.

        // copy number of sectors into number of sectors ready for shifting down

        // Put number of sectors per cluster into Z, and don't shift if there is only
        // one sector per cluster.
        //
        lda [sd_sectorbuffer+$0D]        // because of the checkpoint message above
        taz                                // why store .A in .Z anyway

        and #$fe        // #%1111.1110
        beq ddop_gotclustercount

ddop14:
        // Divide cluster count by two.  This is a 32-bit value, so we have to use
        // ROR to do the shift, and propagate the carry bits between the bytes.
        // This also entails doing it from the last byte, backwards.

        // Get offset of start of (sectors_per_cluster) field
        //
        lda dos_disk_table_offset
        ora #fs_fat32_cluster_count        // is $12

        // get offset of last byte in this field
        //
        clc
        adc #$03
        tay

        ldx #$03
        clc

ddop15: lda dos_disk_table,y
        ror
        sta dos_disk_table,y
        dey
        dex
        bpl ddop15

        tza
        lsr
        taz
        and #$fe
        bne ddop14

ddop_gotclustercount:

// Checkpoint("dos_disk_table-5")
// jsr dump_disk_table        ; debugging

// dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
// dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
// dos_disk_table[10-17] = 00,00,AF,7C,00,00,08,02 -> new data appears
// dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx


        // Re-get sectors per cluster (and store in dos_disk_table entry)
        // (this was destroyed in the calculation above)
        //
        lda dos_disk_table_offset
        ora #fs_fat32_sectors_per_cluster        // is $16
        tay
        lda [sd_sectorbuffer+$0D]
        sta dos_disk_table,y

// Checkpoint("dos_disk_table-6")
// jsr dump_disk_table        ; debugging

// dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
// dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
// dos_disk_table[10-17] = 00,00,AF,7C,00,00,08,02
// dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx

//         ========================

        // filter out non-FAT32 filesystems
        // NOTE: FAT32 can have as few as 65525 clusters, but we do not support
        // such file systems, which should be rare, anyway.

        lda dos_disk_table_offset
        ora #fs_fat32_sectors_per_cluster        // is $16
        tay
        lda #dos_errorcode_too_few_clusters
        sta dos_error_code

        lda dos_disk_table+3,y        // BG this seems to creep-out-of-bounds from +16 to +19
        ora dos_disk_table+2,y
        bne !+
        jmp partitionerror
!:
        // Now get cluster of root directory.
        //
        lda dos_disk_table_offset
        ora #fs_fat32_root_dir_cluster                // is $10
        tay

        ldx #$03
ddop16: lda [sd_sectorbuffer+$2C],x        // +$2c is rootDirFirstCluster[3..0]
        sta dos_disk_table,y
        dex
// BG should there be a "dey" here somewhere?
        bpl ddop16

        // We have now set the following fields:
        //
        // fs_fat32_length_of_fat
        // fs_fat32_system_sectors
        // fs_fat32_reserved_clusters
        // fs_fat32_root_dir_cluster
        // 12,13,14,15 ?
        // fs_fat32_sectors_per_cluster
        // fs_fat32_fat_copies
        // fs_fat32_cluster0_sector

        // Our caller has set:
        //
        // fs_start_sector
        // fs_sector_count

// Checkpoint("dos_disk_table-7")
// jsr dump_disk_table        ; debugging

// dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
// dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
// dos_disk_table[10-17] = 02,00,AF,7C,00,00,08,02 -> new data appears in [10]
// dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx

        // So all that is left for us is to set fs_type_and_source to $0F
        // to indicate FAT32 filesystem on the SD card ...
        //
        lda dos_disk_table_offset
        ora #fs_type_and_source                // is $08
        tay
        lda #$0f
        sta dos_disk_table,y

// jsr dump_disk_table        ; debugging

// dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
// dos_disk_table[08-0F] = 0F,E6,03,00,00,38,02,02 -> new data appears in [08]
// dos_disk_table[10-17] = 02,00,AF,7C,00,00,08,02
// dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx

        Checkpoint("FAT32 partition data copied to dos_disk_table")

        // ... and increment the number of disks we know
        inc dos_disk_count

dos_return_success:

        // Return success
        //
        lda #$00
        sta dos_error_code

        sec
        rts

//         ========================
//         ========================

dos_return_error:

        sta dos_error_code

dos_return_error_already_set:

        clc
        rts

//         ========================

dos_set_current_disk:

        // Is disk number valid?
        //
        // INPUT: .X = disk
        //
        lda #dos_errorcode_no_such_disk
        sta dos_error_code

        cpx dos_disk_count
        bcc !+
        jmp partitionerror        // BG shouldnt this be bmi?
!:
        stx dos_disk_current_disk
        txa
        asl
        asl
        asl
        asl
        asl
        sta dos_disk_table_offset

        ldx dos_disk_current_disk        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty dscd+0
        stx dscd+1

        // print debug message
        //
        jsr checkpoint
        .byte 0
        ascii("dos_set_current_disk=")
dscd:   ascii("xx")
        .byte 0

        sec
        rts

//         ========================

dos_cdroot:

        // Change to root directory on specified disk
        // (Changes current disk if required)
        //
        // INPUT: .X = disk

        jsr dos_set_current_disk
        bcc dos_return_error_already_set

        // get offset of disk entry
        //
        ldx dos_disk_table_offset
        lda [dos_disk_table + fs_fat32_root_dir_cluster +0],x
        sta dos_disk_cwd_cluster
        lda [dos_disk_table + fs_fat32_root_dir_cluster +1],x
        sta dos_disk_cwd_cluster+1

        lda #$00
        sta dos_disk_cwd_cluster+2        // BG here we assume that the 2x MSB's are zero
        sta dos_disk_cwd_cluster+3

        // Nothing else to do, as it doesn't actually affect any existing DOS activity,
        // only future file/directory operations.

        jmp dos_return_success

//         ========================

dos_cluster_to_sector:

        // convert a cluster number in dos_current_cluster into a sector number
        // pre-loaded into SD address registers
        // It is assumed to be on the current disk

        ldx #$03
dcts0:  lda dos_current_cluster,x
        sta $d681,x
        dex
        bpl dcts0

        // subtract 2 from the cluster number (clusters 0 and 1 don't actually exist
        // on FAT32).
        //
        lda #$ff
        tax
        tay
        taz
        lda #$fe
        jsr sdsector_add_uint32

        // now shift it left according to fs_sectors_per_cluster
        //
        ldx dos_disk_table_offset
        lda dos_disk_table+fs_fat32_sectors_per_cluster,x
        tay
        and #$fe
        beq multipliedclusternumber

dcts1:  clc
        rol $D681
        rol $D682
        rol $D683
        rol $D684
        tya
        lsr
        tay
        and #$fe
        bne dcts1

multipliedclusternumber:

        // skip over filesystem reserved and FAT sectors
        //
        lda #fs_fat32_cluster0_sector
        jsr sdsector_add_uint32_from_disktable

        // add start sector of partition
        //
        lda #fs_start_sector
        jsr sdsector_add_uint32_from_disktable

        // XXX - Check that result does not exceed fs_start_sector+fs_sector_count
        // and run over into another partition

        // return success
        sec
        rts

//         ========================

dos_requested_filename_to_uppercase:

        // Convert filename to upper case for comparison
        //
        ldx dos_requested_filename_len
        cpx #$3f
        lda #dos_errorcode_name_too_long
        bcc drftu1
        jmp dos_return_error
drftu1:
        lda dos_requested_filename,x
        jsr toupper
        sta dos_requested_filename,x
        dex
        bpl drftu1
        sec
        rts

//         ========================

dos_get_free_descriptor:

        ldx #$00

dgfd1:  txa
        asl
        asl
        asl
        asl
        tay
        lda [dos_file_descriptors+dos_filedescriptor_offset_diskid],y
        cmp #$FF
        beq dgfd_found_free
        inx
        cpx #dos_filedescriptor_max
        bne dgfd1

        lda #dos_errorcode_too_many_open_files
        jmp dos_return_error

//         ========================

dgfd_found_free:

        // Clear descriptor entry
        //
        ldy #$0f
        lda #$00

dgfd2:  sta dos_file_descriptors,y
        dey
        bne dgfd2

        // Return file descriptor in X
        //
        stx dos_current_file_descriptor
        txa
        asl
        asl
        asl
        asl
        sta dos_current_file_descriptor_offset
        sec
        rts

//         ========================

dos_clearall:

        // Free all file descriptors with extreme prejudice
        // Clear dos_disk_table

        // display debug message to uart
        //
        Checkpoint("dos_clearall:")

        lda #$ff
        sta dos_file_descriptors
        sta dos_file_descriptors+$10
        sta dos_file_descriptors+$20
        sta dos_file_descriptors+$30
        ldx #$00
        lda #$00
dca1:   sta dos_disk_table,x
        inx
        bne dca1
        sec
        rts

//         ========================

dos_closefile:

        // Close the current file/directory
        // If the file is read-only, we can just free the file descriptor and return.
        // XXX - If the file is open for write, we might have a buffer to flush.
        // (Worry about this when we implement writing. Opening files for write will
        // probably require the caller to nominate a 512 byte buffer in user-space
        // memory so that the convenience write-byte routine can work.  The other case,
        // writing a sector at a time, should just be synchronous, so that there is no
        // buffering required.)

        ldx dos_current_file_descriptor_offset
        lda dos_file_descriptors + dos_filedescriptor_offset_mode,x
        cmp #dos_filemode_readwrite
        bne dcf_simple

        // This is where we would flush the write buffer, and update file length in
        // directory, if required.  Note that to save space, we don't actually keep the
        // location of the directory entry of the file in the file descriptor.  This
        // complicates things somewhat, and we might need to change this.  However, the
        // file descriptor table must be a power of two in length, and there isn't any
        // space to double its' size.  Thus we will need a separate table that holds the
        // directory sector and entry for any file being written to.  We might save a
        // few bytes by allowing less than dos_filedescriptor_max files to be open for
        // writing at any point in time.

dcf_simple:

        ldx dos_current_file_descriptor_offset
        lda #$ff // not allocated flag for file descriptor
        sta dos_file_descriptors + dos_filedescriptor_offset_diskid,x
        sec
        rts

//         ========================

dos_openfile:

        // Open the file that is in the dirent structure
        // (to open a file by arbitrary name, you must first call dos_findfile)

        // Check if the file is a directory, if so, refuse to open it.
        //
        lda dos_dirent_type_and_attribs
        and #fs_fat32_attribute_isdirectory
        beq dof_not_a_directory

        lda #dos_errorcode_is_a_directory
        jmp dos_return_error

//         ========================

dof_not_a_directory:

        jsr dos_set_current_file_from_dirent
        bcc l3_dos_return_error_already_set

        jmp dos_open_current_file

//         ========================

dos_findfile:

        // Convenience wrapper around dos_findfirst to make sure that we don't
        // leave any hanging file descriptors.

        jsr dos_findfirst
        php
        jsr dos_closefile
        plp
        bcc l3_dos_return_error_already_set
        sec
        rts

//         ========================

dos_findfirst:

        // Search for file in current directory

        // Convert name to upper case for searching
        //
        jsr dos_requested_filename_to_uppercase
        bcc l3_dos_return_error_already_set

        jsr dos_opendir
        bcs !+
l3_dos_return_error_already_set:
        jmp dos_return_error_already_set
!:
        // Directory is now open, and we can now iterate through directory entries
        //
        jmp dos_findnext


//         ========================

dos_findnext:

        // Keep searching in directory for another match

dff_try_next_entry:

        // Get next directory entry
        //
        jsr dos_readdir
        bcs dff_have_next_entry

        jsr dos_closefile

        lda #dos_errorcode_file_not_found
        jmp dos_return_error

dff_have_next_entry:

        // Compare dos_dirent_longfilename with dos_requested_filename
        //
        jsr dos_dirent_compare_name_to_requested

        // no match? try next entry
        //
        bcc dff_try_next_entry

        // we have a match, so return success
        // (we don't close the file handle for the directory search, because the
        // caller may want to find multiple matches)
        //
        sec
        rts

//         ========================

dos_opendir:

        // Open the current directory as a file
        //
        jsr dos_get_free_descriptor
        bcs !+
        jmp dos_return_error_already_set
!:
        // get offset in file descriptor table
        //
        txa
        asl
        asl
        asl
        asl
        tay

        // set disk id
        //
        lda dos_disk_current_disk
        sta dos_file_descriptors+dos_filedescriptor_offset_diskid,y

        // load cluster of dir into file descriptor
        //
        ldx #$00

dff1:   lda dos_disk_cwd_cluster,x
        sta [dos_file_descriptors+dos_filedescriptor_offset_startcluster],y
        sta [dos_file_descriptors+dos_filedescriptor_offset_currentcluster],y
        iny
        inx
        cpx #$04
        bne dff1

        // Mark file descriptor as being a directory
        //
        ldx dos_current_file_descriptor_offset
        lda #dos_filemode_directoryaccess
        sta [dos_file_descriptors + dos_filedescriptor_offset_mode],x

        jsr dos_open_current_file
        bcs !+
        jmp dos_return_error_already_set
!:      rts

//         ========================

dos_readdir:

        // Get the current file entry, and advance pointer
        // This requires parsing the current directory entry onwards, accumulating
        // long filename parts as required.  We only support filenames to 64 chars,
        // so long names longer than that will get ignored.
        // LFN entries have an attribute byte of $0F (normally indicates volume label)
        // LFN entries use 16-bit unicode values. For now we will just keep the lower
        // byte of these

        // clear long file name data from last call
        //
        lda #0
        sta dos_dirent_longfilename_length

        jsr dos_file_read_current_sector

// debug info, unsure what byte is being displayed...
//
        Checkpoint("-")

        ldy dos_current_file_descriptor_offset
        clc
        lda dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +0,y

        tax                                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty drdcp0+2
        stx drdcp0+3

        ldy dos_current_file_descriptor_offset
        clc
        lda dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +1,y

        tax                                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty drdcp0+0
        stx drdcp0+1

        jsr checkpoint
        .byte 0
        ascii("dos_readdir[")
drdcp0: ascii("xxyy]")
        .byte 0

        jsr dumpsectoraddress        // debug
        jsr dumpfddata                // debug

// end of debug

        ldx dos_current_file_descriptor_offset
        lda [dos_file_descriptors + dos_filedescriptor_offset_mode] ,x
        cmp #dos_filemode_directoryaccess
        beq drd_isdir
        cmp #dos_filemode_end_of_directory
        bne drd_notadir

        lda #dos_errorcode_eof
        jmp dos_return_error

//         ========================

drd_notadir:
        // refuse to read files as directories
        //
        lda #dos_errorcode_not_a_directory
        jmp dos_return_error

//         ========================

drd_isdir:

        // Clear dirent structure
        // WARNING - Uses carnal knowledge to know that dirent structure is
        // 64+1+11+4+4+1 = 85 contiguous bytes
        //
        ldx #[dos_dirent_structure_length-1]
        lda #$00

drce1:  sta dos_dirent_longfilename,x
        dex
        bpl drce1

        // Read current sector
        //
        jsr dos_file_read_current_sector
        bcs !+
        jmp dos_return_error_already_set
!:      jsr sd_map_sectorbuffer

drce_next_piece:

        // Offset in sector correctly indicates where we need to read.
        // Sectors are 512 bytes, so we can't just do a register index.
        // Instead we will setup a 16-bit pointer.
        //
        lda dos_current_file_descriptor_offset
        ora #dos_filedescriptor_offset_offsetinsector
        tax
        lda dos_file_descriptors,x
        sta dos_scratch_vector
        lda dos_file_descriptors+1,x
        clc
        adc #$DE   // high byte of SD card sector buffer
        sta dos_scratch_vector+1

        // (dos_scratch_vector) now has the address of the directory entry

        phx        // as the code below clobbers X

        // print out filename and attrib
        //
        ldy #fs_fat32_dirent_offset_shortname
        ldx #0
eight31:
        lda (<dos_scratch_vector),y
        jsr makeprintable
        sta eight3,x
        iny
        inx
        cpx #11                // 11 chars in the filename (8+3)
        bne eight31
        //
        // attrib
        //
        ldy #fs_fat32_dirent_offset_attributes        // = 0x0B
        lda (<dos_scratch_vector),y
        tax                                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty eight3attrib+0
        stx eight3attrib+1
        //
        // char1
        //
        ldy #$00
        lda (<dos_scratch_vector),y
        tax                                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty eight3char1+0
        stx eight3char1+1

        //

        jsr checkpoint
        .byte 0
        ascii(" (8.3)+(ATTRIB)+(NAME[0]) = ")
eight3: ascii("FILENAMEEXT ")
eight3attrib:
        ascii("xx ")
eight3char1:
        ascii("xx")
        .byte 0

        plx        // as the code above clobbers X

//         ========================

        // first, check if the entry begins with zero, suggesting END-OF-DIRECTORY

        ldy #fs_fat32_dirent_offset_shortname        // Y=0 (first char of entry)
        lda (<dos_scratch_vector),y
        cmp #$00
        bne !+
        jmp drd_end_of_directory
!:
        // then check if the entry begins with $E5, suggesting deleted
        cmp #$e5
        bne !+
        jmp drd_deleted_or_invalid_entry
!:
        // now check the attrib

        ldy #fs_fat32_dirent_offset_attributes        // = 0x0B
        lda (<dos_scratch_vector),y

        // check the kind of data we are looking at:
        // bit 5 = 1         -> is a Archive
        // bit 4 = 1         -> is a Directory
        // bit 3 = 1         -> is a Volume ID
        // bit 2 = 1         -> is a System
        // bit 1 = 1         -> is a Hidden
        // bit 0 = 1         -> is a Readonly

        tay        // for safe keeping

        // if bits xx3210 = xx1111 -> is a long filename
        // we process these differently to the standard (shortname) entries
        //
        and #$0f
        cmp #$0f                // %00001111 LFN entry special attribute value (xxxx1111)
        bne drce_cont0
        jmp drce_longname        // MATCH -> must be LFN

drce_cont0:
        tya        // from safe keeping

        // if bit-4 = 1 -> Directory
        // we ignore directories (for now)
        //
        and #$10
        cmp #$10                // %00010000 Directory
        bne drce_cont1
        jmp drce_directory        // MATCH -> must be Directory

drce_cont1:
        tya        // from safe keeping

        // if bit-3 = 1 -> Vol ID
        // we process the Vol ID different (for now)
        //
        and #$08
        cmp #$08                // %00001000 Vol-ID
        bne drce_cont2
        jmp drce_volumeid        // MATCH -> must be Vol-ID

drce_cont2:
        tya        // from safe keeping

        // check for bits 2 or 1 asserted
        // we should ignore these hidden/system files (for now)
        //
        and #$06                // %00000110
        beq drce_cont3        // branch if equal to zero (ie not Hidden OR System)
        jmp drce_hidden

drce_cont3:

        // was not hidden/system, or Vol-ID, or LFN,
        // so we process this entry regardless of if read-only (bit0) or not

        jmp drce_normalrecord

//         ========================

drce_hidden:

        Checkpoint( "is hidden/system, so skip this record")

        jmp drce_cont_next_part

//         ========================

drce_volumeid:

        Checkpoint( "is Volume ID, so skip this record")

        jmp drce_cont_next_part

//         ========================

drce_directory:

        Checkpoint( "is Directory, so skip this record")

        jmp drce_cont_next_part

//         ========================

drce_longname:

        Checkpoint( "is LFN, so skip this record")

        jmp drce_cont_next_part

        // make sure long entry type is "filename" (=$00)
        //
        ldy #fs_fat32_dirent_offset_lfn_type
        lda (<dos_scratch_vector),y
        beq !+
        jmp drce_normalrecord
!:
        // verify checksum of long name
        // XXX - Actually, we need to keep the checksum, and then compare it with the
        // checksum we compute on the short name to check if this is the right long
        // name.  We are just going to ignore this for now, and assume (and hope) that
        // the LFN structure is always healthy.  I am sure this will come back to bite
        // us at some point, and it can be fixed at that point in time.

        // It's a long filename piece
        // byte 0 gives the position in the LFN of this piece.
        // Each piece has 13 16-bit unicode values.
        // For now, we will only use the lower byte.  later we should gather the
        // long filenames as UTF-16, and then convert them to UTF-8.

        ldy #fs_fat32_dirent_offset_lfn_part_number
        lda (<dos_scratch_vector),y
        and #$3f // mask out end of LFN indicator
        dec_a // subtract one, since pieces are numbered from 1 upwards

        // each piece has 13 chars, and we only allow 64 characters total, so any
        // piece number >4 can be ignored
        //
        cmp #5
        bcs drce_ignore_lfn_piece
        tax
        lda lfn_piece_offsets,x
        tax

        Checkpoint( "found LFN piece <start>")

        // Copy first part of LFN
        //
        ldy #fs_fat32_dirent_offset_lfn_part1_start
        ldz #fs_fat32_dirent_offset_lfn_part1_chars
drce2:  lda (<dos_scratch_vector),y
        beq drce_eot_in_filename
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx
        // protect against over-long LFNs
        cpx #$40
        beq drce_eot_in_filename
        iny
        iny
        dez
        bne drce2

        // Copy second part of LFN
        //
        ldy #fs_fat32_dirent_offset_lfn_part2_start
        ldz #fs_fat32_dirent_offset_lfn_part2_chars
drce3:  lda (<dos_scratch_vector),y
        beq drce_eot_in_filename
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx
        // protect against over-long LFNs
        cpx #$40
        beq drce_eot_in_filename
        iny
        iny
        dez
        bne drce3

        // Copy first part of LFN
        //
        ldy #fs_fat32_dirent_offset_lfn_part3_start
        ldz #fs_fat32_dirent_offset_lfn_part3_chars
drce4:  lda (<dos_scratch_vector),y
        beq drce_eot_in_filename
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx
        // protect against over-long LFNs
        cpx #$40
        beq drce_eot_in_filename
        iny
        iny
        dez
        bne drce4

drce_eot_in_filename:

        Checkpoint("BGOK drce_eot_in_filename")

        // got all characters from this LFN piece
        //
        cpx dos_dirent_longfilename_length
        bcc drce_piece_didnt_grow_name_length
        stx dos_dirent_longfilename_length
        cpx #$3f
        bcs drce_eot_in_filename2

        // null terminate if there is space, for convenience
        //
        lda #$00
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length

drce_eot_in_filename2:

drce_piece_didnt_grow_name_length:

drce_ignore_lfn_piece:

        Checkpoint("BGOK drce_ignore_lfn_piece")

        // We have finished processing this piece of long name.
        // bump directory entry, read next sector if required, and re-enter loop
        // above to keep accumulating

drce_cont_next:

        Checkpoint("BGOK drce_cont_next")

        jsr dos_readdir_advance_to_next_entry
        bcc drce_no_more_pieces

        jmp drce_next_piece

drd_end_of_directory:
        // If we have pieces, then emit the final filename,
        // else return EOF on the directory by falling through to the following
        // Can we ever be in such a position?  Let's assume for the time being that
        // we can't.  If we start losing the last name in a directory list, then we
        // can worry about fixing it then.

        // FALL THROUGH to drce_no_more_pieces

//         ========================

drce_no_more_pieces:
        Checkpoint( "FOUND END_OF_DIRECTORY")

        lda #dos_errorcode_eof
        jmp dos_return_error

//         ========================


drce_cont_next_part:

        jsr dos_readdir_advance_to_next_entry
        bcc !+
        jmp dos_readdir
!:      jmp dos_return_error_already_set

//         ========================

drce_normalrecord:
        // PGS: We have found a short name.


        Checkpoint( "processing SHORT-name")

        // store short name
        //
        ldy #fs_fat32_dirent_offset_shortname

// this test has already been done
//
//         ; Ignore empty and deleted entries (first byte $00 or $E5 respectively)
//         ;
//         lda (<dos_scratch_vector),y
//         beq drd_end_of_directory
//         cmp #$e5
//         beq drd_deleted_or_invalid_entry

        ldx #$00
drce5:  lda (<dos_scratch_vector),y
        sta dos_dirent_shortfilename,x
        inx
        iny
        cpx #11
        bne drce5

        // If we have no long name, copy it also to long name, inserting "." between
        // name and extension as required.
        //
        lda dos_dirent_longfilename_length
        bne drce_already_have_long_name

        // copy name part
        //
        ldy #fs_fat32_dirent_offset_shortname
        ldx #$00
drce7:  lda (<dos_scratch_vector),y
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx
        iny
        cmp #$20            // space indicates end of short name before extension
        beq drce_insert_dot
        cpx #8
        bne drce7
        inx

drce_insert_dot:
        dex
        lda #'.'
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx

        // copy extension part
        //
        ldy #fs_fat32_dirent_offset_shortname+8
        ldz #0
drce6:  lda (<dos_scratch_vector),y
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx
        iny
        inz
        cpz #3  // short name extensions are <=3 chars
        beq drce_copied_extension

        // also terminate extensions early if they are <3 chars
        //
        cmp #$20
        beq drce_copied_extension
        cpx #[8+1+3]
        bne drce6

drce_copied_extension:

        // null terminate short name for convenience in our debugging
        //
        lda #$00
        sta dos_dirent_longfilename,x

        // record length of short name
        stx dos_dirent_longfilename_length

        // fall through

drce_already_have_long_name:

        // now copy attribute field and other useful data

        // starting cluster
        //
        ldy #fs_fat32_dirent_offset_clusters_low
        lda (<dos_scratch_vector),y
        sta dos_dirent_cluster
        iny
        lda (<dos_scratch_vector),y
        sta dos_dirent_cluster+1

        ldy #fs_fat32_dirent_offset_clusters_high
        lda (<dos_scratch_vector),y
        sta dos_dirent_cluster+2
        iny
        lda (<dos_scratch_vector),y
        sta dos_dirent_cluster+3


        // file length in bytes
        //
        ldy #fs_fat32_dirent_offset_file_length
        ldx #0
drce_fl:
        lda (<dos_scratch_vector),y
        sta dos_dirent_length,x
        iny
        inx
        cpx #4
        bne drce_fl

        // attributes
        //
        ldy #fs_fat32_dirent_offset_attributes
        lda (<dos_scratch_vector),y
        sta dos_dirent_type_and_attribs

        Checkpoint( "drce_fl populated fields")

        jsr dos_readdir_advance_to_next_entry
        bcs drce_not_eof

drce_is_eof:

        Checkpoint( "DEBUG drce_is_eof <!>")

        // We need to pass the error through here to indicate EOF in directory,
        // but in a way that can be defered to the next call to dos_readdir, because
        // we have a valid entry right now.  We do this with a special file mode which
        // is EOF of directory (dos_filemode_end_of_directory)
        //
        ldx dos_current_file_descriptor_offset
        lda #dos_filemode_end_of_directory
        sta dos_file_descriptors + dos_filedescriptor_offset_mode ,x

        ldx dos_current_file_descriptor_offset
        lda [dos_file_descriptors + dos_filedescriptor_offset_mode],x

        sec
        rts

drce_not_eof:

        Checkpoint( "drce_not_eof CHECK<1/3>")

        // Ignore zero-length filenames (corresponding to empty directory entries)
        //
        lda dos_dirent_longfilename_length
        cmp #0
        beq l_dos_readdir

        Checkpoint( "drce_not_eof CHECK<2/3>")

        lda dos_dirent_shortfilename
        beq l_dos_readdir
        cmp #$20
        bne !+
l_dos_readdir:
        jmp dos_readdir
!:
        Checkpoint( "drce_not_eof CHECK<3/3>")

        ldx dos_dirent_longfilename_length
        jsr lfndebug

        sec
        rts

//         ========================

lfndebug:
        // requires .X to be set
        //
                                        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty fnmsg1-5
        stx fnmsg1-4

        // Show what we have in the filename so far
        //
        phx        // safekeep

        ldx #29
drce23: lda dos_dirent_longfilename,x
        jsr makeprintable
        sta fnmsg1,x
        dex
        bpl drce23

        plx        // unsafekeep

        jsr checkpoint
        .byte 0
        ascii("LFN(xx): ") // the "xx" can be replaced with the name_length
fnmsg1: ascii("..............................") // BG: why only 30 chars?
        .byte 0

        rts

//         ========================

drd_deleted_or_invalid_entry:

        tax
                                        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty ddie+0
        stx ddie+1

        jsr checkpoint
        .byte 0
ddie:        ascii("xx drd_deleted_or_invalid_entry")
        .byte 0

        jsr dos_readdir_advance_to_next_entry
        bcc !+
        jmp dos_readdir
!:
        jmp dos_return_error_already_set

//         ========================

lfn_piece_offsets:
        .byte 0,13,13*2,13*3,13*4

//         ========================

dos_dirent_compare_name_to_requested:

        // print debug message showing what we are comparing

        // print filename for debug

        // Do the cheap check of comparing the lengths first
        //
        lda dos_dirent_longfilename_length
        cmp dos_requested_filename_len
        bne dff3

        // lengths match, so compare bytes
        // XXX - Needs to support * and ?
        // see http://6502.org/source/strings/patmatch.htm for a routine to take
        // inspiration from.
        //
        ldx dos_dirent_longfilename_length
        dex
dff4:   lda dos_dirent_longfilename,x
        cmp dos_requested_filename,x
        bne dff3
        dex
        bne dff4

        // File names match, so return success

        Checkpoint("Found the file...")

        sec
        rts

dff3:
        // file names don't match, so return failure
        clc
        rts

//         ========================

dos_readdir_advance_to_next_entry:

        ldy dos_current_file_descriptor_offset

        clc
        lda dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +0,y
        adc #$20 // length of FAT32/VFAT directory entry
        sta dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +0,y
        bne dratne_done

        // Increment upper byte
        //
        lda dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +1,y
        inc_a
        cmp #$01
        bne drce_end_of_sector
        sta dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +1,y

dratne_done:
        sec
        rts

//         ========================

drce_end_of_sector:

        // Reset pointer back to start of sector
        //
        lda #$00
        sta dos_file_descriptors+dos_filedescriptor_offset_offsetinsector+1,y

        jsr dos_file_advance_to_next_sector
        rts

//         ========================

dos_set_current_file_from_dirent:

        // copy start cluster from dirent to start and current cluster
        //
        jsr dos_get_free_descriptor
        jsr dos_get_file_descriptor_offset
        bcs !+
        jmp dos_return_error_already_set
!:
        // set disk id
        //
        lda dos_disk_current_disk
        sta dos_file_descriptors+dos_filedescriptor_offset_diskid,x

        // set current cluster to start cluster
        //
        ldy #0
dscffd1:
        lda dos_dirent_cluster,y
        sta dos_file_descriptors+dos_filedescriptor_offset_startcluster,x
        sta dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        inx
        iny
        cpy #4
        bne dscffd1

        jsr dos_get_file_descriptor_offset
        bcs !+
        jmp dos_return_error_already_set
!:

        // set disk id
        //
        lda dos_disk_current_disk
        sta dos_file_descriptors+dos_filedescriptor_offset_diskid,x

        // set mode
        //
        lda #dos_filemode_readonly
        sta dos_file_descriptors+dos_filedescriptor_offset_mode,x

        // set sector in cluster (set to 0)
        //
        lda #$00
        sta dos_file_descriptors+dos_filedescriptor_offset_sectorincluster,x

        // set offset in sector (set to 0)
        //
        sta dos_file_descriptors+dos_filedescriptor_offset_offsetinsector+0,x
        sta dos_file_descriptors+dos_filedescriptor_offset_offsetinsector+1,x

        // Get length of file, so that we can
        // limit load to reported length of file, instead assuming cluster
        // chain is correct length, and file ends on a cluster boundary
        ldx #$03
!:      lda dos_dirent_length,x
        sta dos_bytes_remaining,x
        dex
        bpl !-
	
        sec
        rts

//         ========================

dos_open_current_file:

        // copy start cluster to current cluster, and zero position in file
        //
        jsr dos_get_file_descriptor_offset
        bcs !+
        jmp dos_return_error_already_set
!:
        // Copy start cluster to current cluster
        //
        ldy #3
docf1:  lda dos_file_descriptors + dos_filedescriptor_offset_startcluster   ,x
        sta dos_file_descriptors + dos_filedescriptor_offset_currentcluster ,x
        inx
        dey
        bpl docf1

        jsr dos_get_file_descriptor_offset
        lda #$00

        // sectorincluster, offsetinsector, fileoffset are contiguous, which allows
        // us to clear these more efficiently.
        //
        ldy #6
docf2:  sta dos_file_descriptors+dos_filedescriptor_offset_sectorincluster,x
        inx
        dey
        bne docf2

        jsr dos_get_file_descriptor_offset

        sec
        rts

//         ========================

        // Load A & X with the offset of the current file descriptor, relative to
        // dos_file_descriptors.

dos_get_file_descriptor_offset:

        lda dos_current_file_descriptor
        cmp #4
        bcs dos_bad_file_descriptor
        asl
        asl
        asl
        asl
        tax
        sec
        rts

//         ========================

dos_bad_file_descriptor:

        lda #dos_errorcode_invalid_file_descriptor
        jmp dos_return_error

//         ========================

dos_set_current_cluster_from_file:

        // copy cluster number in file to current cluster
        //
        jsr dos_get_file_descriptor_offset
        bcc @l2_dos_return_error_already_set

        ldy #$00
dfrcs1: lda dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        sta dos_current_cluster,y
        inx
        iny
        cpy #$04
        bne dfrcs1
        rts

//         ========================

dos_file_read_current_sector:

        jsr dos_get_file_descriptor_offset
        jsr dos_set_current_cluster_from_file
        jsr dos_cluster_to_sector

        // Add sector within cluster
        //
        jsr dos_get_file_descriptor_offset
        bcs @gotFDOffset
@l2_dos_return_error_already_set:
        jmp dos_return_error_already_set
@gotFDOffset:

        // Set A to the offset of the sectorincluster field of the current
        // file descriptor
        //
        ora #dos_filedescriptor_offset_sectorincluster

        // Now put that offset in y, so that we can load the sector number in the
        // current cluster for the current file descriptor
        //
        tay
        lda dos_file_descriptors,y

        // add sector number in cluster to current sector number (which is the
        // start of the cluster)
        //
        jsr sdsector_add_uint8

        jmp sd_readsector

//         ========================

dos_file_advance_to_next_sector:

        // Increment file position offset by 2 pages
        //
        ldx dos_current_file_descriptor_offset

        lda dos_file_descriptors + dos_filedescriptor_offset_fileoffset+0 ,x
        clc
        adc #$02
        sta dos_file_descriptors + dos_filedescriptor_offset_fileoffset+0 ,x
        bcc dfatns1
        inc dos_file_descriptors + dos_filedescriptor_offset_fileoffset+1 ,x
        bne dfatns1
        inc dos_file_descriptors + dos_filedescriptor_offset_fileoffset+2 ,x
dfatns1:

        // increase sector
        //
        inc dos_file_descriptors + dos_filedescriptor_offset_sectorincluster ,x
        lda dos_file_descriptors + dos_filedescriptor_offset_sectorincluster ,x
        ldy dos_disk_table_offset

        cmp dos_disk_table + fs_fat32_sectors_per_cluster ,y

        // and if necessary, advance to next cluster
        //
        beq dos_file_advance_to_next_cluster
        sec
        rts

//         ========================

dos_file_advance_to_next_cluster:

        // set to sector 0 in cluster
        //
        ldy dos_current_file_descriptor_offset
        lda #$00
        sta dos_file_descriptors+dos_filedescriptor_offset_sectorincluster,y

        // read chained cluster number for fs_clusternumber

        // FAT32 uses 32-bit cluster numbers.
        // the text below may be misleading, as we have 8 sectors per cluster
        // 512 / 4 = 128 cluster numbers per sector.
        // To get the sector of the FAT containin a particular
        // cluster entry, we thus need to shift the cluster number
        // right 7 bits.  Then we add the start sector number of the FAT.

        jsr dos_set_current_cluster_from_file

        // copy cluster to sector number
        //
        ldx #$03
dfanc1:
        lda dos_current_cluster,x
        sta dos_current_sector,x
        dex
        bpl dfanc1

        // Remember low byte of cluster number so that we can pull the
        // cluster number for the next cluster out of the FAT sector
        //
        lda dos_current_cluster
        sta dos_scratch_byte_1

        jsr dos_cluster_to_fat_sector

	jsr dos_remember_sd_sector
	
        // copy from current cluster to SD sector address register
        //
        ldx #$03
        php
dfanc41:
        lda dos_current_cluster,x
        sta $d681,x
        dex
        bpl dfanc41

dfanc44:
        plp
        lda dos_current_cluster,x
        adc #$00
        sta dos_current_cluster,x
        php
        inx
        cpx #$04
        bne dfanc44

        plp

        // read FAT sector
        //
        jsr sd_readsector
        bcs @readSectorOk
        jmp dos_return_error_already_set
@readSectorOk:

        jsr sd_map_sectorbuffer

        // now read the right four bytes out.
        // cluster number needs to be shifted left 2 bits.
        // we only need the lowest order byte.
        // Get low byte of old cluster number from dos_scratch_byte_1
        // where we put it.
        //
        lda dos_scratch_byte_1
        asl
        asl
        tax

        // get offset to current cluster field in current file descriptor ...
        lda dos_current_file_descriptor_offset
        ora #dos_filedescriptor_offset_currentcluster
        tay

        // ... and keep it handy, because we will need it a few times
        //
        sty dos_scratch_byte_2

        // get offset of current cluster number field in file descriptor
        // so that we can write the new cluster number in there.
        //
        ldy dos_scratch_byte_2

        ldz #$00
        lda dos_scratch_byte_1
        and #$40
        bne dfanc_high

dfanc6: lda $de00,x
        sta dos_file_descriptors,y
        inx
        iny
        inz
        cpz #$04
        bne dfanc6
        bra dfanc_check

dfanc_high:
        lda $df00,x
        sta dos_file_descriptors,y
        inx
        iny
        inz
        cpz #$04
        bne dfanc_high

dfanc_check:
        // check that resulting cluster number is valid.

//         jsr debug_show_cluster_number

        // get current cluster field address again
        //
        ldy dos_scratch_byte_2

        // First, only the lower 28-bits are valid
        //
        lda dos_file_descriptors+3,y
        and #$0f
        sta dos_file_descriptors+3,y

        // Now check for special values:
        // cluster 0 is invalid
        //
        lda dos_file_descriptors+3,y
        ora dos_file_descriptors+2,y
        ora dos_file_descriptors+1,y
        ora dos_file_descriptors,y
        cmp #$00
        beq dfanc_fail

        // $FFFFFF7 = bad cluster
        // $FFFFFFF = end of file
        // (we'll treat anything from $FFFFFF0-F as bad/invalid for simplicity)
        lda dos_file_descriptors+3,y
        cmp #$0f
        bne dfanc_ok
        lda dos_file_descriptors+2,y
        and dos_file_descriptors+1,y
        cmp #$ff
        bne dfanc_ok
        lda dos_file_descriptors,y
        and #$f0
        cmp #$f0
        beq dfanc_fail

dfanc_ok:
        // cluster number is okay
	jsr dos_restore_sd_sector
        sec
        rts

dfanc_fail:
	jsr dos_restore_sd_sector
        lda #dos_errorcode_invalid_cluster
        jmp dos_return_error

	// Some routines disturb the current SD card sector in the buffer,
	// but where the caller might not expect or want this to happen.
	// For this reason we have the following convenience routines for
	// stashing and restoring the current ready sector.
dos_remember_sd_sector:
	ldx #3
!:	lda $d681,x
	sta dos_stashed_sd_sector_number,x
	dex
	bpl !-
	rts

dos_restore_sd_sector:
	ldx #3
!:	lda dos_stashed_sd_sector_number,x
	sta $d681,x
	dex
	bpl !-
	jsr sd_readsector
	rts
	
	
//         ========================

dos_cluster_to_fat_sector:
        // Take dos_current_cluster, as a cluster number,
        // and compute the absolute sector number on the SD card
        // where that cluster must live.
        // INPUT: dos_current_cluster = cluster number
        // OUTPUT: dos_current_cluster = absolute sector, which
        //         contains the FAT sector that has the FAT entry
        //         corresponding to the requested cluster number.

        // shift right 7 times = divide by 128
        //
        ldy #$07
dfanc2: clc
        ror dos_current_cluster+3
        ror dos_current_cluster+2
        ror dos_current_cluster+1
        ror dos_current_cluster+0
        dey
        bne dfanc2

        // add start of partition offset
        //
        ldy dos_disk_table_offset
        ldx #$00
        clc
        php
dfanc3: plp
        lda dos_current_cluster,x
        adc dos_disk_table + fs_start_sector ,y
        sta dos_current_cluster,x
        php
        iny
        inx
        cpx #$04
        bne dfanc3
        plp

        // add start of fat offset
        //
        ldy dos_disk_table_offset
        ldx #$00
        clc
        php
dfanc4: plp
        lda dos_current_cluster,x
        adc dos_disk_table + fs_fat32_system_sectors ,y
        sta dos_current_cluster,x
        php
        iny
        inx
        cpx #$02
        bne dfanc4

        plp

        rts

//         ========================

dos_print_current_cluster:

        // prints a message to the screen
        //
        ldx #<msg_clusternumber
        ldy #>msg_clusternumber
        jsr printmessage
        ldy #$00
        ldz dos_current_cluster+3
        jsr printhex
        ldz dos_current_cluster+2
        jsr printhex
        ldz dos_current_cluster+1
        jsr printhex
        ldz dos_current_cluster+0
        jsr printhex

        Checkpoint("dos_print_current_cluster")

        rts

//         ========================

dos_readfileintomemory:

        // assumes that filename is already set using "dos_setname", which
        // copies filename string into "dos_requested_filename",
        //        and sets length into "dos_requested_filename_length".
        //
        // assumes that the 32-bit load-address pointer is set by
        // storing load-address at "dos_file_loadaddress+{0-3}"

        // print some debug information
        //
        //         jsr dos_print_current_cluster

        // Clear number of sectors read
        ldx #$00
        stx dos_sectorsread
        stx dos_sectorsread+1

        jsr dos_findfirst
        php

        // close directory now that we have what we were looking for ...
        //
        jsr dos_closefile
        plp

        // ... but report if we hit an error
        //
        bcc l_dos_return_error_already_set

        jsr dos_openfile
        bcc l_dos_return_error_already_set

        jsr sd_map_sectorbuffer

        jmp drfim_sector_loop

l_dos_return_error_already_set:
        jmp dos_return_error_already_set

//         ========================

drfim_sector_loop:

        jsr dos_file_read_current_sector
        bcc drfim_eof

        // copy sector to memory
        //

        // Work out how many bytes of this page we need to read
        jsr dos_load_y_based_on_dos_bytes_remaining

//         phy
//
//         ldx <dos_file_loadaddress+3
//         jsr checkpoint_bytetohex
//         sty loadingaddr+0
//         stx loadingaddr+1
//         ldx <dos_file_loadaddress+2
//         jsr checkpoint_bytetohex
//         sty loadingaddr+2
//         stx loadingaddr+3
//         ldx <dos_file_loadaddress+1
//         jsr checkpoint_bytetohex
//         sty loadingaddr+4
//         stx loadingaddr+5
//         ldx <dos_file_loadaddress+0
//         jsr checkpoint_bytetohex
//         sty loadingaddr+6
//         stx loadingaddr+7
//
//         jsr checkpoint
//         .byte 0,"Loading @ "
// loadingaddr:
//         .byte "$$$$$$$$",13,10,0
//
//         ply

        ldx #$00
        ldz #$00

        // Actually write the bytes to memory that have been loaded
drfim_rr1:
        lda sd_sectorbuffer,x                // is $DE00
        nop // 32-bit pointer access follows
        sta_bp_z(<dos_file_loadaddress)
        inz // dest offset
        inx // src offset
        dey // bytes in page to copy
        bne drfim_rr1

        inw <dos_file_loadaddress+1

        // Work out how many bytes of this page we need to read
        jsr dos_load_y_based_on_dos_bytes_remaining

        // Actually write the bytes to memory that have been loaded
drfim_rr1b:
        lda sd_sectorbuffer+$100,x        // is $DF00
        nop // 32-bit pointer access follows
        sta_bp_z(<dos_file_loadaddress)
        inz // dest offset
        inx // src offset
        dey // bytes in page to copy
        bne drfim_rr1b

        jsr dos_file_advance_to_next_sector
        bcc drfim_eof

        // We only allow loading into a 16MB space
        // Provided that we check the load address before starting,
        // this ensures that a user-land request cannot load a huge file
        // that eventually overwrites the hypervisor and results in privilege
        // escalation.
        // This restriction to a 16MB space is implemented by only incrementing the middle 2 bytes of
        // the address, instead of all 3 upper bytes.
        //
        inw <dos_file_loadaddress+1

        // Increment number of sectors read (16 bit valie)
        //
        inc dos_sectorsread
        bne drfim_sector_loop

        inc dos_sectorsread+1
        // see if there is another sector
        bne drfim_sector_loop

        jsr dos_closefile

        // File is >65535 sectors (32MB), report error
        //
        lda #dos_errorcode_file_too_long
        jmp dos_return_error

//         ========================

drfim_eof_pop_pc:
        pla
        pla

drfim_eof:

        jsr dos_closefile
        jmp dos_return_success

dos_load_y_based_on_dos_bytes_remaining:
        ldy #$00
        lda dos_bytes_remaining+1
        ora dos_bytes_remaining+2
        ora dos_bytes_remaining+3
        bne !+
        lda dos_bytes_remaining+0
        // If no more bytes to read, then jump to EOF
        beq drfim_eof_pop_pc
        ldy dos_bytes_remaining+0
        lda #$00
        sta  dos_bytes_remaining+0
        rts
!:
        lda dos_bytes_remaining+1
        sec
        sbc #$01
        sta dos_bytes_remaining+1
        lda dos_bytes_remaining+2
        sbc #0
        sta dos_bytes_remaining+2
        lda dos_bytes_remaining+3
        sbc #0
        sta dos_bytes_remaining+3
        rts


dos_readfile:

	lda dos_bytes_remaining+0
	ora dos_bytes_remaining+1
	ora dos_bytes_remaining+2
	ora dos_bytes_remaining+3
	bne !+

	// End of file: So zero bytes returned
	lda #$00
	sta hypervisor_x
	sta hypervisor_y
	clc
	rts
	
!:
	// Indicate how many bytes we are returning
	ldx #<$0200
	ldy #>$0200
	
	lda dos_bytes_remaining+2
	ora dos_bytes_remaining+3
	bne !+   // lots more to read
	lda dos_bytes_remaining+1
	cmp #1
	bcs !+   // at least a whole sector more to read

	// Only a fractional part of a sector to read, so zero out remaining

	// Update number of bytes for fractional sector read
	ldx dos_bytes_remaining+0
	ldy dos_bytes_remaining+1
	
	lda #$00
	sta dos_bytes_remaining+0
	// Actually make it look like 1 sector to go, so we decrement that to zero
	// immediately below
	lda #$02
	sta dos_bytes_remaining+1
	// FALL THROUGH
!:
	// Deduct one sector from the remaining
	lda dos_bytes_remaining+1
	sec
	sbc #2
	sta dos_bytes_remaining+1
	lda dos_bytes_remaining+2
	sbc #0
	sta dos_bytes_remaining+2
	lda dos_bytes_remaining+3
	sbc #0
	sta dos_bytes_remaining+3

	// Store number of bytes read in X and Y for calling process
	stx hypervisor_x
	sty hypervisor_y
	
	// Now read sector and return
	
        jsr sd_map_sectorbuffer
        jsr dos_file_read_current_sector
        bcs drf_gotsector
	rts
	
drf_gotsector:
	// Then advance to next sector.
	// Ignore the error, as the EOF will get picked up on the next call.

	jsr dos_file_advance_to_next_sector

	sec
	rts
	
	
//         ========================

dos_setname:

        // INPUT: .X .Y = pointer to filename,
        //                 filename string must be terminated with $00
        //                 filename string must be <= $3F chars

        stx dos_scratch_vector
        sty dos_scratch_vector+1
        ldy #$00

lr11:   lda (<dos_scratch_vector),y
        sta dos_requested_filename,y
        beq dsn_eon
        iny
        cpy #$40
        bne lr11

        lda #0
        sta dos_requested_filename_len
        lda #dos_errorcode_name_too_long
        clc
        rts

dsn_eon:
        sty dos_requested_filename_len

        sec
        rts

//         ========================

dos_d81detach:
	// Detaches both drive 0 and drive 1
	
        lda #$00
        sta $d68b

        // Mark it as unmounted (but preserve other flags for remounting, e.g., if it should be write-enabled)
        lda currenttask_d81_image0_flags
        ora #d81_image_flag_mounted
        eor #d81_image_flag_mounted
        sta currenttask_d81_image0_flags

        // But we leave the file name there, in case someone wants to re-mount the image.
        // This is exactly what happens when a process is unfrozen: dos_d81detach is called,
        // followed by dos_d81attach, after first retrieving the filename
        sec
        rts

dos_d81attach0:

	//  Always works on drive 0
	
        // Assumes only that D81 file name has been set with dos_setname.
        //
        jsr dos_findfile
        bcs d81a1

        lda #dos_errorcode_file_not_found
        clc
        rts

//         ========================

d81a1:        // XXX - Why do we call closefile here?
        jsr dos_closefile

	jsr dos_d81check
	bcs d81a1a
	rts
d81a1a:	

        // copy sector number from $D681 to $D68c
        //
        ldx #$03
l94d:   lda $d681,x		// resolved sector number
        sta $d68c,x  		// sector number of disk image #0
        dex
        bpl l94d
	
        // Set flags to indicate it is mounted (and read-write)
        // But don't mess up the flags for the 2nd drive
	lda $d68b
	and #%10111000
        ora #$03
        sta $d68b

	// And set the MEGAfloppy flag if the file is 64MiB long
	lda d81_clustercount+1
	cmp #$80
	bne not_mega_floppy2

	lda $d68b
	and #%10111000
        ora #$43
	sta $d68b

not_mega_floppy2:	

        Checkpoint("dos_d81attach0 <success>")

        // Save name and set mount flag for disk image in process descriptor block
        lda #d81_image_flag_mounted
        sta currenttask_d81_image0_flags

        ldx dos_requested_filename_len

        // Check if the filename of the disk image is too long
        cpx #d81_image_max_namelen
        bcs @d81NameTooLongForProcessDescriptor

        // Name not too long, save name and length
        stx currenttask_d81_image0_namelen
        ldx #0
!:      lda dos_requested_filename,x
        sta currenttask_d81_image0_name,x
        inx
        cpx currenttask_d81_image0_namelen
        bne !-

        sec
        rts

@d81NameTooLongForProcessDescriptor:
        // Name is too long, so don't save it.
        // This means that the disk image will unmount on freeze, and will not re-mount after
        // XXX - This should probably be an error.
        lda #0
        sta currenttask_d81_image0_namelen

        sec
        rts

dos_d81attach1:

	//  Always works on drive 0
	
        // Assumes only that D81 file name has been set with dos_setname.
        //
        jsr dos_findfile
        bcs d81a1b

        lda #dos_errorcode_file_not_found
        clc
        rts

//         ========================

d81a1b:        // XXX - Why do we call closefile here?
        jsr dos_closefile

	jsr dos_d81check

	bcs d81a1ab
	rts
d81a1ab:	

        // copy sector number from $D681 to $D68c
        //
        ldx #$03
l94db:   lda $d681,x		// resolved sector number
        sta $d690,x  		// sector number of disk image #1
        dex
        bpl l94db
		
        // Set flags to indicate it is mounted (and read-write)
        // But don't mess up the flags for the 2nd drive
	lda $d68b
	and #%01000111
        ora #$18
        sta $d68b

	// And set the MEGAfloppy flag if the file is 64MiB long
	lda d81_clustercount+1
	cmp #$80
	bne not_mega_floppy2b

	lda $d68b
	and #%01000111
        ora #$98
	sta $d68b

not_mega_floppy2b:	
	
        Checkpoint("dos_d81attach1 <success>")

        // Save name and set mount flag for disk image in process descriptor block
        lda #d81_image_flag_mounted
        sta currenttask_d81_image1_flags

        ldx dos_requested_filename_len

        // Check if the filename of the disk image is too long
        cpx #d81_image_max_namelen
        bcs @d81NameTooLongForProcessDescriptor1

        // Name not too long, save name and length
        stx currenttask_d81_image1_namelen
        ldx #0
!:      lda dos_requested_filename,x
        sta currenttask_d81_image1_name,x
        inx
        cpx currenttask_d81_image1_namelen
        bne !-

        sec
        rts

@d81NameTooLongForProcessDescriptor1:
        // Name is too long, so don't save it.
        // This means that the disk image will unmount on freeze, and will not re-mount after
        // XXX - This should probably be an error.
        lda #0
        sta currenttask_d81_image1_namelen

        sec
        rts

	
dos_d81check:	
        // now we need to check that the file is long enough,
        // and also that the clusters are contiguous.

        // Start by opening the file
        //
        jsr dos_set_current_file_from_dirent
        bcc @fileNotOpenedOk

        jsr dos_openfile
        bcs @fileOpenedOk
@fileNotOpenedOk:
        jmp nod81
@fileOpenedOk:

        // work out how many clusters we need
        // We need 1600 sectors, so halve for every zero tail
        // bit in sectors per cluster.  we can do this because
        // clusters in FAT must be 2^n sectors.
        //
        lda #$00
        sta d81_clustercount
        sta d81_clustercount+1
        lda #<1600
        sta d81_clustersneeded
        lda #>1600
        sta d81_clustersneeded+1

        // get sectors per cluster of disk
        //
        ldx dos_disk_table_offset
        lda dos_disk_table+fs_fat32_sectors_per_cluster,x
        taz

l94:    tza
        and #$01
        bne d81firstcluster
        tza
        lsr
        taz
        lsr d81_clustersneeded+1
        ror d81_clustersneeded
        jmp l94

d81firstcluster:
        // Get current cluster of D81 file, so that
        // we can check that clusters in file are contiguous
        //
        ldx dos_current_file_descriptor_offset
        ldy #0

l94b:   lda dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        sta d81_clusternumber,y
        inx
        iny
        cpy #4
        bne l94b

d81nextcluster:
        // Now read through clusters and make sure that all is
        // well.

        // check that it matches expected cluster number
        //
        ldx dos_current_file_descriptor_offset
        ldy #0

l94a:   lda dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        cmp d81_clusternumber,y
        bnel d81isfragged
        inx
        iny
        cpy #4
        bne l94a

        // increment number of clusters found so far
        //
        inc d81_clustercount
        bne l96
        inc d81_clustercount+1
l96:

        // increment expected cluster number
        //
        clc
        lda d81_clusternumber
        adc #$01
        sta d81_clusternumber
        lda d81_clusternumber+1
        adc #$00
        sta d81_clusternumber+1
        lda d81_clusternumber+2
        adc #$00
        sta d81_clusternumber+2
        lda d81_clusternumber+3
        adc #$00
        sta d81_clusternumber+3

        jsr dos_file_advance_to_next_cluster
        bcs d81nextcluster

        // The above continues until EOF is reached, so clear DOS
        // error after.
        //
        lda #$00
        sta dos_error_code

        Checkpoint("dos_d81attach <measured end of image>")

        jsr dos_closefile

        // we have read to end of D81 file, and it is contiguous
        // now check that it is the right length

	// First check if we read enough for 64MiB
	// XXX - This currently assumes 8 sectors per cluster.
	lda d81_clustercount+1
	cmp #$80
	bne not_mega_floppy
	lda d81_clustercount+0
	ora d81_clustercount+2
	ora d81_clustercount+3
	beq is_mega_floppy

not_mega_floppy:	
	// Is a 64MiB MEGA Floppy?
	// (These behave as double-sided 256-track 256-sector disks of 512 byte sectors,
	//  but with normal D81 directory format on side 0 of track 40.)
	// XXX These are really quite big, much bigger than required.
	// We should allow masking of the upper bits to allow for arbitrarily smaller sized
	// MEGAfloppies, so that space can be more efficiently used.	
	
        lda d81_clustersneeded
        cmp d81_clustercount
        bne d81wronglength

        lda d81_clustersneeded+1
        cmp d81_clustercount+1
        bne d81wronglength
is_mega_floppy:	

d81_is_good:	
        // D81 is good.

        // Get cluster number again, convert to sector, and copy to
        // SD controller FDC emulation disk image offset registers
        //
        ldx dos_current_file_descriptor_offset
        ldy #0

l94c:   lda dos_file_descriptors+dos_filedescriptor_offset_startcluster,x
        sta dos_current_cluster,y
        inx
        iny
        cpy #4
        bne l94c

        jsr dos_cluster_to_sector

	sec
	rts
	

//         ========================

d81wronglength:
        Checkpoint("dos_d81attach <wrong length>")

        lda #dos_errorcode_image_wrong_length
        sta dos_error_code
        clc
        rts

//         ========================

d81isfragged:
        Checkpoint("dos_d81attach <fragmented>")

        lda #dos_errorcode_image_fragmented
        sta dos_error_code
        clc
        rts

//         ========================

nod81:
        Checkpoint("dos_d81attach <file not found>")

        clc
        rts

//         ========================

sdsector_add_uint8:

        pha
        lda #0
        tax
        tay
        taz
        pla
        // FALL THROUGH to sdsector_add_uint32

sdsector_add_uint32:

        // Add the 32-bit value contained in A,X,Y,Z to
        // $D681-$D684, the SD card sector number.
        //
        clc
        adc $D681
        sta $D681
        txa
        adc $d682
        sta $d682
        tya
        adc $d683
        sta $d683
        tza
        adc $d684
        sta $d684
        ldz #$00
        rts

//         ========================

sdsector_add_uint32_from_disktable:

        ora dos_disk_table_offset
        tay
        ldx #$00
        clc
        php
l23:    plp
        lda $D681,x
        adc dos_disk_table,y
        sta $D681,x
        php
        iny
        inx
        cpx #$04
        bne l23
        plp
        rts

//         ========================

makeprintable:
        // Convert unprintable ASCII characters to question marks

        cmp #$20
        bcc unprintable
        cmp #$7f
        bcs unprintable
        rts

unprintable:
        lda #$3f
        rts

//         ========================
