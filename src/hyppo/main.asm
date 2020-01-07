/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    -------------------------------------------------------------------
    Purpose:
    1. Verify checksum of ROM area of slow RAM.
    2. If checksum fails, load complete ROM from SD card.
    3. Select default disk image for F011 emulation.

    The hyppo ROM is 16KB in length, and maps at $8000-$BFFF
    in hypervisor mode.

    Hyppo modifies RAM from $0000-$07FFF (ZP, stack, 40-column
    screen, 16-bit text mode) during normal boot.

    BG: is the below true still, I dont think so.
    If Hyppo needs to load the ROM from SD card, then it may
    modify the first 64KB of fast ram.

    We will use the convention of C=0 means failure, ie CLC/RTS,
                              and C=1 means success, ie SEC/RTS.


    This included file defines many of the alias used throughout
    it also suggests some memory-map definitions
    ---------------------------------------------------------------- */

#import "constants.asm"
#import "macros.asm"
#import "machine.asm"

.label TrapEntryPoints_Start        = $8000
.label RelocatedCPUVectors_Start    = $81f8
.label Traps_Start                  = $8200
.label DOSDiskTable_Start           = $bb00
.label SysPartStructure_Start       = $bbc0
.label DOSWorkArea_Start            = $bc00
.label ProcessDescriptors_Start     = $bd00
.label HyppoStack_Start             = $be00
.label HyppoZP_Start                = $bf00
.label Hyppo_End                    = $bfff
.label Data_Start                   = $ce00

.file [name="../../bin/HICKUP.M65", type="bin", segments="TrapEntryPoints,RelocatedCPUVectors,Traps,DOSDiskTable,SysPartStructure,DOSWorkArea,ProcessDescriptors,HyppoStack,HyppoZP"]

.segmentdef TrapEntryPoints        [min=TrapEntryPoints_Start,     max=RelocatedCPUVectors_Start-1                         ]
.segmentdef RelocatedCPUVectors    [min=RelocatedCPUVectors_Start, max=Traps_Start-1                                       ]
.segmentdef Traps                  [min=Traps_Start,               max=DOSDiskTable_Start-1                                ]
.segmentdef DOSDiskTable           [min=DOSDiskTable_Start,        max=SysPartStructure_Start-1,                           ]
.segmentdef SysPartStructure       [min=SysPartStructure_Start,    max=DOSWorkArea_Start-1                                 ]
.segmentdef DOSWorkArea            [min=DOSWorkArea_Start,         max=ProcessDescriptors_Start-1                          ]
.segmentdef ProcessDescriptors     [min=ProcessDescriptors_Start,  max=HyppoStack_Start-1                                  ]
.segmentdef HyppoStack             [min=HyppoStack_Start,          max=HyppoZP_Start-1,            fill, fillByte=$3e      ]
.segmentdef HyppoZP                [min=HyppoZP_Start,             max=Hyppo_End,                  fill, fillByte=$3f      ]
.segmentdef Data                   [min=Data_Start,                max=$ffff                                               ]

/*  -------------------------------------------------------------------
    Reserved space for Hyppo ZP at $BF00-$BFFF
    ---------------------------------------------------------------- */
        .segment HyppoZP
        * = HyppoZP_Start

        // Temporary vector storage for DOS
        //
dos_scratch_vector:
        .word 0,0
dos_scratch_byte_1:
        .byte 0
dos_scratch_byte_2:
        .byte 0

        // Vectors for copying data between hypervisor and user-space
        //
hypervisor_userspace_copy_vector:
        .word 0

        // general hyppo temporary variables
        //
zptempv:
        .word 0
zptempv2:
        .word 0
zptempp:
        .word 0
zptempp2:
        .word 0
zptempv32:
        .word 0,0
zptempv32b:
        .word 0,0
dos_file_loadaddress:
        .word 0,0

        // Used for checkpoint debug system of hypervisor
        //
checkpoint_a:
        .byte 0
checkpoint_x:
        .byte 0
checkpoint_y:
        .byte 0
checkpoint_z:
        .byte 0
checkpoint_p:
        .byte 0
checkpoint_pcl:
        .byte 0
checkpoint_pch:
        .byte 0

        // SD card timeout handling
        //
sdcounter:
        .byte 0,0,0

/*  -------------------------------------------------------------------
    Scratch space in ZP space usually used by kernel
    we try to use address space not normally used by C64 kernel, so
    that it is possible to make calls to hyppo after boot. Eventually
    the desire is to have an SYS call that brings up a menu that lets
    you choose a disk image from a list.
    ---------------------------------------------------------------- */

        .segment Data
        * = Data_Start
romslab:
        .byte 0
screenrow:
        .byte 0
checksum:
        .dword 0
file_pagesread:
        .word 0

        // Variables for testing of D81 boot image
d81_clusternumber:
        .dword 0
d81_clustersneeded:
        .word 0
d81_clustercount:
        .word 0

        .segment TrapEntryPoints
        * = TrapEntryPoints_Start

/*  -------------------------------------------------------------------
    CPU Hypervisor Trap entry points.
    64 x 4 byte entries for user-land traps.
    some more x 4 byte entries for system traps (reset, page fault etc)
    ---------------------------------------------------------------- */

trap_entry_points:

        // Traps $00-$07 (user callable)
        //
        jmp dos_and_process_trap                // Trap #$00 (unsure what to call it)
        nop                                     // refer: hyppo_dos.asm
        jmp memory_trap                         // Trap #$01
        nop                                     // refer: hyppo_mem.asm
        jmp syspart_trap                        // Trap #$02
        nop                                     // refer: hyppo_syspart.asm
        jmp serialwrite                         // Trap #$03
        nop                                     // refer serialwrite in this file
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Traps $08-$0F (user callable)
        //
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Traps $10-$17 (user callable)
        //
        jmp nosuchtrap
        nop
        jmp securemode_trap
        nop
        jmp leave_securemode_trap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Traps $18-$1F (user callable)
        //
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Traps $20-$27 (user callable)
        //
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Traps $28-$2F (user callable)
        //
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Traps $30-$37
        //
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        jmp protected_hardware_config           // Trap #$32 (Protected Hardware Configuration)
        nop                                     // refer: hyppo_task


        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Traps $38-$3F (user callable)
        //
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Traps $40-$4F (reset, page fault and other system-generated traps)
        jmp reset_entry                         // Trap #$40 (power on / reset)
        nop                                     // refer: below in this file

        jmp page_fault                          // Trap #$41 (page fault)
        nop                                     // refer: hyppo_mem

        jmp restore_press_trap                  // Trap #$42 (press RESTORE for 0.5 - 1.99 seconds)
        nop                                     // refer: hyppo_task "1000010" x"42"

        jmp matrix_mode_toggle                  // Trap #$43 (C= + TAB combination)
        nop                                     // refer: hyppo_task

        jmp f011_virtual_read                   // Trap #$44 (virtualised F011 sector read)
        nop

        jmp f011_virtual_write                  // Trap #$45 (virtualised F011 sector write)
        nop

        jmp nosuchtrap                          // common-trap (catch all)
        nop                                     // refer: below in this file
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop
        jmp nosuchtrap
        nop

        // Leave room for relocated cpu vectors below
        //
        .segment RelocatedCPUVectors
        * = RelocatedCPUVectors_Start

        // Then we have relocated CPU vectors at $81F8-$81FF
        // (which are 2-byte vectors for interrupts, not 4-byte
        // trap addresses).
        // These are used to catch interrupts in hypervisor mode
        // (although the need for them may have since been removed)
        .word reset_entry    // unused vector
        .word hypervisor_nmi // NMI
        .word reset_entry    // RESET
        .word hypervisor_irq // IRQ

        .segment Traps
        * = Traps_Start

/*  -------------------------------------------------------------------
    Hypervisor traps
    ---------------------------------------------------------------- */

/*  -------------------------------------------------------------------
    Illegal trap / trap sub-function handlers

    Traps are triggered by writing to $D640-$D67F
    and trap to $8000+((address & $3F)*4) in the hypervisor

    Routine for unimplemented/reserved traps
    (Consider replacing with trap to hypervisor error screen with option
    to return?)
    ---------------------------------------------------------------- */
nosuchtrap:

        // Clear C flag for caller to indicate failure
        //
        lda hypervisor_flags
        and #$FE   // C flag is bit 0
        sta hypervisor_flags

        // set A to $FF
        //
        lda #$ff
        sta hypervisor_a

        // return from hypervisor
        //
        sta hypervisor_enterexit_trigger

//         ========================

return_from_trap_with_success:

        // Return from trap with C flag clear to indicate success

        jsr sd_unmap_sectorbuffer

        // set C flag for caller to indicate success
        //
        lda hypervisor_flags
        ora #$01   // C flag is bit 0
        sta hypervisor_flags

        Checkpoint("return_from_trap_with_success")

        // return from hypervisor
        sta hypervisor_enterexit_trigger

//         ========================

return_from_trap_with_failure:

        jsr sd_unmap_sectorbuffer

        // report error in A
        //
        sta hypervisor_a
        lda hypervisor_flags
        and #$fe   // C flag is bit 0 (ie clear bit-0)
        sta hypervisor_flags

        Checkpoint("return_from_trap_with_failure")

        // return from hypervisor
        sta hypervisor_enterexit_trigger

//         ========================

invalid_subfunction:

        jmp nosuchtrap

//         ========================

/*  -------------------------------------------------------------------
    System Partition functions
    ---------------------------------------------------------------- */
#import "syspart.asm"

/*  -------------------------------------------------------------------
    Freeze/Unfreeze functions
    ---------------------------------------------------------------- */
#import "freeze.asm"

/*  -------------------------------------------------------------------
    DOS, process control and related functions trap
    ---------------------------------------------------------------- */
#import "dos.asm"
#import "dos_write.asm"

/*  -------------------------------------------------------------------
    Virtual memory and memory management
    ---------------------------------------------------------------- */
#import "mem.asm"

/*  -------------------------------------------------------------------
    Task (process) management
    ---------------------------------------------------------------- */
#import "task.asm"

/*  -------------------------------------------------------------------
    Secure mode / compartmentalised operation management
    ---------------------------------------------------------------- */
#import "securemode.asm"

/*  -------------------------------------------------------------------
    SD-Card and FAT related functions
    ---------------------------------------------------------------- */
#import "sdfat.asm"

/*  -------------------------------------------------------------------
    Virtualised F011 access (used for disk over serial monitor)
    ---------------------------------------------------------------- */
#import "virtual_f011.asm"

/*  -------------------------------------------------------------------
    Audio mixer control functions
    ---------------------------------------------------------------- */
#import "audiomix.asm"

/*  -------------------------------------------------------------------
    MEGAphone I2C register setup
    ---------------------------------------------------------------- */
#import "megaphone.asm"

/*  -------------------------------------------------------------------
    CPU Hypervisor Entry Point on reset
    ---------------------------------------------------------------- */

reset_machine_state:
        // get CPU state sensible
        sei
        cld
        see

        // Disable reset watchdog (this happens simply by writing anything to
        // this register)
        // Enable /EXROM and /GAME from cartridge port (bit 0)
        // enable flat 32-bit addressing (bit 1)
        // do not engage ROM write protect (yet) (bit 2)
        // do make ASC/DIN / CAPS LOCK control CPU speed (bit 3)
        // do not force CPU to full speed (bit 4)
        // also force 4502 CPU personality (6502 personality is still incomplete) (bit 5)
        // and clear any pending IRQ or NMI event (bit 6)
        //
        // (The watchdog was added to catch reset problems where the machine
        // would run off somewhere odd instead of resetting properly. Now it
        // will auto-reset after 65535 cycles if the watchdog is not cleared).
        //

        lda #$6b    // 01101011
        sta hypervisor_feature_enables

        lda #$ff
        sta $d7fd

        jsr audiomix_setup
        // enable audio amplifier
        lda #$01
        sta audioamp_ctl

        // Clear system partition present flag
        lda #$00
        sta syspart_present

        // disable IRQ/NMI sources
        lda #$7f
        sta $DC0D
        sta $DD0D
        lda #$00
        sta $D01A

        sec
        // determine VIC mode and set it accordingly in VICIV_MAGIC
        jsr enhanced_io

        // clear UART interrupt status
        lda uart65_irq_flag

        // switch to fast mode
        // 1. C65 fast-mode enable
        lda $d031
        ora #$40
        sta $d031
        // 2. MEGA65 48MHz enable (requires C65 or C128 fast mode to truly enable, hence the above)
        lda #$c5
        sta $d054

        // Setup I2C peripherals on the MEGAphone platform
        jsr megaphone_setup

        // sprites off, and normal mode
        lda #$00
        sta $d015
        sta $d055
        sta $d06b
        sta $d057
        lda $d049
        and #$f
        sta $d049
        lda $d04b
        and #$f
        sta $d04b
        lda $d04d
        and #$f
        sta $d04d
        lda $d04f
        and #$f
        sta $d04f

        // We DO NOT need to mess with $01, because
        // the 4510 starts up with hyppo mapped at $8000-$BFFF
        // enhanced ($FFD3xxx) IO page mapped at $D000,
        // and fast RAM elsewhere.

        // Map SD card sector buffer to SD card, not floppy drive
        lda #$80
        sta sd_buffer_ctrl

        // Access cartridge IO area to force EXROM probe on R1 PCBs
        // XXX DONT READ $DExx ! This is a known crash causer for Action Replay
        // cartridges.  $DF00 should be okay, however.
        // XXX $DFxx can also be a problem for other cartridges, so we shouldn't do either.
        // this will mean cartridges don't work on the R1 PCB, but as that is no longer being
        // developed for, we can just ignore that now, and not touch anything.
        //lda $df00

        jsr resetdisplay
        jsr erasescreen
        jsr resetpalette

        // note that this first message does not get displayed correctly
        Checkpoint("reset_machine_state")
        // but this second message does
        Checkpoint("reset_machine_state")

        rts

/*  -------------------------------------------------------------------
    CPU Hypervisor reset/trap routines
    ---------------------------------------------------------------- */
reset_entry:
        sei

#import "debugtests.asm"

        jsr reset_machine_state

        // display welcome screen
        //
        ldx #<msg_hyppo
        ldy #>msg_hyppo
        jsr printmessage

        // leave a blank line below hyppo banner
        //
        ldx #<msg_blankline
        ldy #>msg_blankline
        jsr printmessage

        // Display GIT commit
        //
        ldx #<msg_gitcommit
        ldy #>msg_gitcommit
        jsr printmessage

        // Display help text
        //
        ldx #<msg_hyppohelp
        ldy #>msg_hyppohelp
        jsr printmessage

        // check keyboard for 0-9 down to select alternate rom
        //
        jsr keyboardread

        // Magic instruction used by monitor_load to work out where
        // to patch. Monitor_load changes bit to JMP when patching for
        // SD-cardless operation
        bit go64
        bit $1234

//         ========================

normalboot:

        jsr dump_disk_count        // debugging to Checkpoint
        jsr dumpcurrentfd        // debugging to Checkpoint

        // Try to read the MBR from the SD card to ensure SD card is happy
        //
        ldx #<msg_tryingsdcard
        ldy #>msg_tryingsdcard
        jsr printmessage

        // Work out if we are using primary or secondard SD card

        // First try resetting card 0
        lda #$c0
        sta $d680
        lda #$00
        sta $d680
        lda #$01
        sta $d680

        ldx #$03
@morewaiting:
        jsr sdwaitawhile

        lda $d680
        and #$03
        bne trybus1

        phx

        ldx #<msg_usingcard0
        ldy #>msg_usingcard0
        jsr printmessage

        plx

        jmp tryreadmbr
trybus1:
        dex
        bne @morewaiting

        lda #$c1
        sta $d680

        ldx #<msg_tryingcard1
        ldy #>msg_tryingcard1
        jsr printmessage

        // Try resetting card 1
        lda #$00
        sta $d680
        lda #$01
        sta $d680

        jsr sdwaitawhile

        lda $d680
        and #$03
        beq tryreadmbr

        // No working SD card -- we can just try booting to BASIC, since we
        // now include our open-source ROM
        ldx #<msg_nosdcard
        ldy #>msg_nosdcard
        jsr printmessage
        jmp go64

tryreadmbr:
        jsr readmbr
        bcs gotmbr

        // check for keyboard input to jump to utility menu
        jsr scankeyboard
        bcs nokey2
        cmp #$20
        bne nokey2
        jmp utility_menu
nokey2:

        // Oops, cant read MBR
        // display debug message to screen
        //
        ldx #<msg_retryreadmbr
        ldy #>msg_retryreadmbr
        jsr printmessage

        // put sd card sector buffer back after scanning
        // keyboard
        lda #$81
        tsb sd_ctrl

        // display debug message to uart
        //
        Checkpoint("re-try reading MBR of sdcard")

        jmp tryreadmbr

//         ========================

gotmbr:
        // good, was able to read the MBR

        // Scan SD card for partitions and mount them.
        //
        jsr dos_clearall
        jsr dos_read_partitiontable

        // then print out some useful information
        //
        ldx #<msg_diskcount
        ldy #>msg_diskcount
        jsr printmessage
        //
        ldy #$00
        ldz dos_disk_count
        jsr printhex
        //
        ldy #$00
        ldz dos_default_disk
        jsr printhex

        jsr dump_disk_count     // debugging to Checkpoint
        jsr dumpcurrentfd       // debugging to Checkpoint
//             jsr print_disk_table        ; debugging to Screen

//         ========================

        // If we have no disks, offer the utility menu
        lda dos_disk_count
        bne @thereIsADisk
        jmp utility_menu
@thereIsADisk:

        // Go to root directory on default disk
        //
        ldx dos_default_disk
        jsr dos_cdroot
        bcs mountsystemdiskok

        // failed
        //
        ldx #<msg_cdrootfailed
        ldy #>msg_cdrootfailed
        jsr printmessage
        ldy #$00
        ldz dos_error_code
        jsr printhex

        Checkpoint("FAILED CDROOT")
        //
        // BG: should probably JMP to reset or something, and not fall through


mountsystemdiskok:

        // Load and display boot logo
        // Prepare 32-bit pointer for loading boot logo @ $0057D00
        // (palette is $57D00-$57FFF, logo $58000-$5CFFF)
        lda #$7d
        sta <dos_file_loadaddress+1
        lda #$00
        sta <dos_file_loadaddress+0
        // lda #$05
        sta <dos_file_loadaddress+2
        // lda #$00
        sta <dos_file_loadaddress+3

        ldx #<txt_BOOTLOGOM65
        ldy #>txt_BOOTLOGOM65
        jsr dos_setname

        // print debug message
        //
        Checkpoint("  try-loading BOOTLOGO")

        jsr dos_readfileintomemory
        bcs logook

//         ========================

        // FAILED: print debug message
        //
        Checkpoint("  FAILED-loading BOOTLOGO")

        // print debug message
        //
        ldx #<msg_nologo
        ldy #>msg_nologo
        jsr printmessage
        ldy #$00
        ldz dos_error_code
        jsr printhex

        Checkpoint("FAILED loading BOOTLOGO")

//         ========================

logook:
        // Loaded banner, so copy palette into place
        jsr setbannerpalette

        // iterate through directory entries looking for ordinary file
        // HICKUP.M65 to load into hypervisor memory ...
        // ... but only if we are not running a hick-up'd hyppo now.
        //
        lda hypervisor_hickedup_flag        // $d67e = register for hickup-state (00=virgin, else already-hicked)
        bpl allowhickup

        // already hicked
        //
        ldx #<msg_alreadyhicked
        ldy #>msg_alreadyhicked
        jsr printmessage

        jmp posthickup

//         ========================

allowhickup:        // BG was label nextdirectoryentry3:

        // Prepare 32-bit pointer for loading hickup @ $0004000
        //
        // We load it at $4000, which is mapped to first 64KB RAM, and then
        // have a routine also in RAM that we use to copy the loaded data
        // back onto the Hyppo "ROM" space, so that there are no problems
        // with the copying code being changed while it being replaced.
        //
        lda #$00
        sta <dos_file_loadaddress+0
        lda #$40
        sta <dos_file_loadaddress+1
        lda #$00
        sta <dos_file_loadaddress+2
        lda #$00
        sta <dos_file_loadaddress+3

        ldx #<txt_HICKUPM65
        ldy #>txt_HICKUPM65
        jsr dos_setname

        // print debug message
        //
        Checkpoint("  try-loading HICKUP")

        jsr dos_readfileintomemory
        bcc nohickup

//         ========================

        // We have loaded a hickup file, so jump into it.

        // print debug message
        //
        Checkpoint("  loaded OK HICKUP")

//                 ldx #<msg_hickuploaded
//                 ldy #>msg_hickuploaded
//                 jsr printmessage

        ldy #$00
        ldz <zptempv32+3        // BG what is in this register? Where is the data set?
        jsr printhex
        ldz <zptempv32+2
        jsr printhex
        ldz <zptempv32+1
        jsr printhex
        ldz <zptempv32+0
        jsr printhex

dohickup:
        // Use DMAgic to copy $0004000-$0007FFF to $FFF8000-$FFFBFFF
        // (We have to copy the routine to do this to RAM, since we will
        // be replacing ourselves)
        ldx #$00
krc:        lda hickuproutine,x
        sta $3000,x
        inx
        bne krc
        jmp $3000

//         ========================

hickuproutine:
        // The following routine gets copied as-is to $3000 and run from there.
        // The DMA list is still available in the hyppo ROM when it gets
        // called, so we can just use it there, instead of working out where
        // it gets copied to

        // NOTE that only 256-bytes are copied, so the hickuproutine and hickupdmalist
        //      cannot exceed this limit, else revise the krc routine.

        // Set bottom 22 bits of DMA list address as for C65
        // (8MB address range).  Hyppo ROM is at $FFF8000, so $FF goes
        // in high-byte area
        //
        lda #$ff
        sta $d702
        lda #$ff
        sta $d704  // dma list is in top MB of address space
        lda #>hickupdmalist
        sta $d701
        // Trigger enhanced DMA
        lda #<hickupdmalist
        sta $d705

        // copy complete, so mark ourselves upgraded, and jump into hypervisor
        // as though we were just reset.

        // (it doesn't matter what gets written to this register, it is just the fact that it has been
        // written to, that sets the flag).
        //
        sta hypervisor_hickedup_flag        // mark ourselves as having hicked up, (00=virgin, else already-hicked)
        jmp $8100

//         ========================

hickupdmalist:
        // MEGA65 Enhanced DMA options
        .byte $0A  // Request format is F018A
        .byte $80,$00 // Source is $00xxxxx
        .byte $81,$FF // Destination is $FF
        .byte $00  // No more options
        // copy $0004000-$0007FFF to $FFF8000-$FFFBFFF
        // F018A DMA list
        // (MB offsets get set in routine)
        .byte $00 // copy + last request in chain
        .word $4000 // size of copy is 16KB
        .word $4000 // starting at $4000
        .byte $00   // of bank $0
        .word $8000 // destination address is $8000
        .byte $0F   // of bank $F
        .word $0000 // modulo (unused)

//         ========================

couldntopenhickup:

nohickup:
//                 ldx #<msg_nohickup
//                 ldy #>msg_nohickup
//                 jsr printmessage

posthickup:

        // MILESTONE: Have file system properties.

        // Look for MEGA65.D81 to mount for F011 emulation

        // print debug message
        //
        Checkpoint("  Here we are POST-HICKUP")

        jsr dumpcurrentfd        // debugging to Checkpoint

        // for now indicate that there is no disk in drive
        // (unless we notice that floppy access has been virtualised)
        lda hypervisor_hardware_virtualisation
        and #$01
        bne f011Virtualised
        lda #$00
        sta sd_f011_en        // f011 emulation
f011Virtualised:

        // Go to root directory on default disk
        //
        ldx dos_default_disk
        jsr dos_cdroot
        bcs @notSDCardError
        jmp sdcarderror
@notSDCardError:

        // Re-set virtual screen row length after touching $D06F
        lda #80
        sta $d058

        // set name of file we are looking for
        //
        ldx #<txt_MEGA65D81
        ldy #>txt_MEGA65D81
        jsr dos_setname

        // print debug message
        //
        Checkpoint("  try-mounting MEGA65.D81")

        jsr dos_findfile
        bcc d81attachfail
        jsr dos_closefile

        jsr dos_d81attach0
        bcc d81attachfail

        ldx #<msg_d81mounted
        ldy #>msg_d81mounted
        jsr printmessage

        // print debug message
        //
        Checkpoint("  mounted MEGA65.D81")

        // all done, move on to loading the ROM
        //
        jmp findrom

//         ========================

d81attachfail:
        // we couldn't find the D81 file, so tell the user
        //
        ldx #<msg_nod81
        ldy #>msg_nod81
        jsr printmessage
        ldy #$00
        ldz dos_error_code
        jsr printhex

        // debug
        Checkpoint( "couldnt mount/attach MEGA65.D81")

findrom:
        // Check state of current ROM
        //
        jsr checkromok
        bcc loadrom

        // ROM is loaded and ready, so transfer control to it.
        //
        ldx #<msg_romok
        ldy #>msg_romok
        jsr printmessage

        Checkpoint("JUMPing into ROM-code")

        // check for keyboard input to jump to utility menu
        jsr scankeyboard
        bcs nokey3
        cmp #$20
        bne nokey3
        jmp utility_menu
nokey3: jmp go64

//         ========================

attempt_loadcharrom:
        // Load CHARROM.M65 into character ROM
        //
        ldx #<txt_CHARROMM65
        ldy #>txt_CHARROMM65
        jsr dos_setname

        // Prepare 32-bit pointer for loading whole ROM ($FF7E000)
        //
        lda #$00
        sta <dos_file_loadaddress+0
        lda #$E0
        sta <dos_file_loadaddress+1
        lda #$F7
        sta <dos_file_loadaddress+2
        lda #$0F
        sta <dos_file_loadaddress+3

        jmp dos_readfileintomemory

attempt_loadc65rom:
        ldx #<txt_MEGA65ROM
        ldy #>txt_MEGA65ROM
        jsr dos_setname

        // Prepare 32-bit pointer for loading whole ROM ($0020000)
        //
        lda #$00
        sta <dos_file_loadaddress+0
        sta <dos_file_loadaddress+1
        sta <dos_file_loadaddress+3
        lda #$02
        sta <dos_file_loadaddress+2

        jmp dos_readfileintomemory

attempt_load1541rom:
        ldx #<txt_1541ROM
        ldy #>txt_1541ROM
        jsr dos_setname

        // Prepare 32-bit pointer for loading whole ROM ($FFDC000)
        //
        lda #$00
        sta <dos_file_loadaddress+0
        lda #$C0
        sta <dos_file_loadaddress+1
        lda #$FD
        sta <dos_file_loadaddress+2
        lda #$0F
        sta <dos_file_loadaddress+3

        jmp dos_readfileintomemory

loadrom:

        jsr dumpcurrentfd        // debugging to Checkpoint

        // ROMs are not loaded, so try to load them, or prompt
        // for user to insert SD card
        //
//                 ldx #<msg_rombad
//                 ldy #>msg_rombad
//                 jsr printmessage

        // print debug message
        //
        Checkpoint("  try-loading CHAR-ROM")

        jsr attempt_loadcharrom
        bcs loadedcharromok

//         ========================

        // FAILED
//                 ldx #<msg_charrombad
//                 ldy #>msg_charrombad
//                 jsr printmessage

        // print debug message
        //
//                 Checkpoint(" couldnt load CHARROM.M65")

        jmp loadc65rom

//         ========================

loadedcharromok:
        // print debug message
        //
        Checkpoint("  OK-loading CHARROM")

        // prepare debug message
        //
        ldx dos_current_file_descriptor_offset
        lda dos_file_descriptors + dos_filedescriptor_offset_fileoffset+0,x
        sta file_pagesread
        lda dos_file_descriptors + dos_filedescriptor_offset_fileoffset+1,x
        sta file_pagesread+1

        ldx #<msg_charromloaded
        ldy #>msg_charromloaded
        jsr printmessage
        ldy #$00
        ldz file_pagesread+1
        jsr printhex
        ldz file_pagesread
        jsr printhex

loadc65rom:

        jsr dumpcurrentfd        // debugging to Checkpoint

        // print debug message
        //
        Checkpoint("  try-loading MEGA65-ROM")

        jsr attempt_loadc65rom
        bcs loadedok

//         ========================

        // ROM not found: indicate which ROM we were looking for
        //
        ldx #$0b
l17d:   lda txt_MEGA65ROM,x
        sta msg_romnotfound+19,x
        dex
        bne l17d
        ldx #<msg_romnotfound
        ldy #>msg_romnotfound
        jsr printmessage

        jsr sdwaitawhile
        jsr sdwaitawhile
        jsr sdwaitawhile
        jsr sdwaitawhile

        jmp sdcarderror

//         ========================

        // ROM was found and loaded
loadedok:
        ldx dos_current_file_descriptor_offset
        lda dos_file_descriptors + dos_filedescriptor_offset_fileoffset +0,x
        sta file_pagesread
        lda dos_file_descriptors + dos_filedescriptor_offset_fileoffset +1,x
        sta file_pagesread+1

        // check the size of the loaded file
        // i.e., that we have loaded $0200 x $100 = $20000 = 128KiB
        lda file_pagesread+1
        cmp #$00
        bne @romFileNotTooShort
@romFileIsTooShort:
        jmp romfiletooshort
@romFileNotTooShort:
        cmp #$01
        beq @romFileIsTooShort
        cmp #$02
        bne @romFileIsTooLong
        lda file_pagesread
        beq @romFileNotTooLong
@romFileIsTooLong:
        jmp romfiletoolong
@romFileNotTooLong:

        // the loaded ROM was OK in size

        jsr syspart_dmagic_autoset

        // Store checksum of ROM
        //
        jsr storeromsum

        // copy character ROM portion into place
        // i.e., copy $2Dxxx to $FF7Exxx

        lda #$ff
        sta $d702
        sta $d704
        lda #$00
        lda #>charromdmalist
        sta $d701
        lda #<charromdmalist
        sta $d705

        jmp loadedmegaromok

charromdmalist:
        // M65 DMA options
        .byte $0A    // Request format is F018A
        .byte $81,$FF // destination is $FFxxxxx
        .byte $00 // no more options
        // F018A DMA list
        .byte $00
        .word $1000
        .word $D000
        .byte $02
        .word $E000
        .byte $07
        .word $0000

loadedmegaromok:

        // prepare debug message
        //
        ldx dos_current_file_descriptor_offset
        lda dos_file_descriptors + dos_filedescriptor_offset_fileoffset+0,x
        sta file_pagesread
        lda dos_file_descriptors + dos_filedescriptor_offset_fileoffset+1,x
        sta file_pagesread+1

        ldx #<msg_megaromloaded
        ldy #>msg_megaromloaded
        jsr printmessage
        ldy #$00
        ldz file_pagesread+1
        jsr printhex
        ldz file_pagesread
        jsr printhex

        // ROM file loaded, transfer control
        //
        ldx #<msg_romok
        ldy #>msg_romok
        jsr printmessage

        // print debug message
        //
        Checkpoint("  OK-loaded MEGA65-ROM")

        jsr attempt_load1541rom
        bcs loaded1541rom

        Checkpoint("  FAIL loading 1541 ROM")

        ldx #<msg_no1541rom
        ldy #>msg_no1541rom
        jsr printmessage

loaded1541rom:
        jsr dumpcurrentfd        // debugging to Checkpoint

        // check for keyboard input to jump to utility menu
        jsr utility_menu_check
        jsr scankeyboard
        bcs nokey4
        cmp #$20
        bne nokey4
        jmp utility_menu
nokey4:

        jmp go64

//         ========================

romfiletoolong:
        ldx #<msg_romfilelongerror
        ldy #>msg_romfilelongerror
        jsr printmessage
        ldz file_pagesread+1
        jsr printhex
        ldz file_pagesread
        jsr printhex
        jsr sdwaitawhile
        jmp reset_entry

romfiletooshort:
        ldx #<msg_romfileshorterror
        ldy #>msg_romfileshorterror
        jsr printmessage
        ldz file_pagesread+1
        jsr printhex
        ldz file_pagesread
        jsr printhex
        jsr sdwaitawhile
        jmp reset_entry

//         ========================

fileopenerror:
        ldx #<msg_fileopenerror
        ldy #>msg_fileopenerror
        jsr printmessage

sdcarderror:
        ldx #<msg_sdcarderror
        ldy #>msg_sdcarderror
        jsr printmessage

        jsr sdwaitawhile
        jmp reset_entry

//         ========================

badfs:
        ldx #<msg_badformat
        ldy #>msg_badformat
        jsr printmessage

        jsr sdwaitawhile
        jmp reset_entry

/*  -------------------------------------------------------------------
    ROM loading and manipulation routines
    ---------------------------------------------------------------- */

checkromok:
        // read switch 13.  If set, assume ROM is invalid
        //
        lda fpga_switches_high
        and #$20
        bne checksumfails

        // or if loading a ROM other than MEGA65.ROM, then assume ROM
        // is invalid
        //
        lda txt_MEGA65ROM+6
        cmp #'.'
        bne checksumfails

        // calculate checksum of loaded ROM ...
        //
        jsr calcromsum
        // ... then fall through to testing it
testromsum:
        // have checksum for all slabs.

        jsr mapromchecksumrecord

        lda $4000
        cmp checksum
        bne checksumfails
        lda $4001
        cmp checksum+1
        bne checksumfails
        lda $4002
        cmp checksum+2
        bne checksumfails

        jsr resetmemmap

        sec
        rts

//         ========================

        // check failed
checksumfails:
        clc
        rts

//         ========================

storeromsum:
        jsr mapromchecksumrecord

        lda checksum
        sta $4000
        lda checksum+1
        sta $4001
        lda checksum+2
        sta $4002
        rts

//         ========================

mapromchecksumrecord:

        // Map in ROM load record, and compare checksum
        // Here we have to use our extension to MAP to access >1MB
        // as only 128KB of slow ram is shadowed to $20000.
        //
        // Again, we have to take the relative nature of MAP, so
        // we ask for $FC000 to be mapped at $0000, which means that
        // $4000 will correspond to $0000 (MAP instruction address
        // space wraps around at the 1MB mark)

        // select 128MB mark for mapping lower 32KB of address space
        //
        lda #$80
        ldx #$0f
        ldy #$00   // keep hyppo mapped at $8000-$BFFF
        ldz #$3f

        map

        // then map $FC000 + $4000 = $00000 at $4000-$7FFF
        //
        lda #$c0
        ldx #$cf
        ldy #$00   // keep hyppo mapped at $8000-$BFFF
        ldz #$3f
        map
        eom

        rts

//         ========================

calcromsum:        // calculate checksum of 128KB ROM

        // use MAP to map C65 ROM address space in 16KB
        // slabs at $4000-$7FFF.  Check sum each, and
        // then compare checksum to ROM load record.
        //
        // ROMs get loaded into slow RAM at $8020000-$803FFFF,
        // which is shadowed for reading using C65 MAP instruction to
        // C65 address space $20000-$3FFFF.
        //
        // Checksum and ROM load record are stored in
        // $8000000 - $800FFFF, i.e., the first 64KB of
        // slow RAM.
        //
        // The 4510 MAP instruction does not normally provide access to the
        // full 28-bit address space, so we need to use a trick.
        //
        // We do this by interpretting a MAP instruction that says to
        // map none of the 8KB pages, but provides an offset in the range
        // $F0000 - $FFF00 to set the "super page" register for that 32KB
        // moby to bits 8 to 15 of the offset.  In practice, this means
        // to allow mapping of memory above 1MB, the MB of memory being
        // selected is chosen by the contents of A and Y registers when
        // X and Z = $0F.
        //

        // reset checksum
        // checksum is not all zeroes, so that if RAM initialises with
        // all zeroes, including in the checksum field, the checksum will
        // not pass.
        //
        lda #$03
        sta checksum
        sta checksum+1
        sta checksum+2
        sta checksum+3

        // start with bottom 16KB of ROM
        // we count in 16KB slabs, and ROM starts at 128KB mark,
        // so we want to check from the 8th to 15th slabs inclusive.
        //
        lda #$08
        sta romslab

        // Summing can be done using normal use of MAP instruction,
        // since slow RAM is shadowed as ROM to $20000-$3FFFF

sumslab:
        // romcheckslab indicates which 16KB piece.
        // MAP uses 256-byte granularity, so we need to shift left
        // 6 bits into A, and right 2 bits into X.
        // We then set the upper two bits in X to indicate that the mapping
        // applies to blocks 2 and 3.
        // BUT MAP is relative, and since we are mapping at the 16KB mark,
        // we need to subtract 1 lot of 16KB from the result.
        // this is easy -- we just sbc #$01 from romslab before using it.
        //
        lda romslab
        sec
        sbc #$01
        lsr
        lsr
        ora #$c0
        tax
        lda romslab
        sec
        sbc #$01
        asl
        asl
        asl
        asl
        asl
        asl
        ldy #$00   // keep hyppo mapped at $8000-$BFFF
        ldz #$3f

        map
        eom

        // sum contents of 16KB slab
        //
        lda #$00
        sta <zptempv
        lda #$40
        sta <zptempv+1

sumpage:
        ldy #$00
sumbyte:
        lda checksum
        clc
        adc (<zptempv),y
        sta checksum
        bcc l6
        inc checksum+1
        bcc l6
        inc checksum+2
l6:     iny
        bne sumbyte
        inc <zptempv+1
        lda <zptempv+1
        cmp #$80
        bne sumpage

        inc romslab
        lda romslab
        cmp #$10
        bne sumslab

        jmp resetmemmap

/*  -------------------------------------------------------------------
    Display and basic IO routines
    ---------------------------------------------------------------- */

resetdisplay:
        // reset screen
        //
        lda #$40        // 0100 0000 = choose charset
        sta $d030        // VIC-III Control Register A

        lda $d031        // VIC-III Control Register B
        and #$40        // bit-6 is 4mhz
        sta $d031

        lda #$00        // black
        sta $D020        // border
        sta $D021        // background

        // Start in 60Hz mode, since most monitors support it
        // (Also required to make sure matrix mode pixels aren't ragged on first boot).
        lda #$80
        sta $d06f
	// Enable HDMI 44.1KHz audio 
	lda #$03
	sta $d61a

        // disable test pattern and various other strange video things that might be hanging around
        lda #$80
        trb $d066
        lda #$00
        sta $d06a // bank# for screen address
        sta $d06b // 16-colour sprites
        sta $d078 // sprite Y super MSBs
        sta $d05f // sprite X super MSBs
        lda #$78
        sta $d05a // correct horizontal scaling
        lda #$C0
        sta $D05D // enable hot registers, raster delay
        lda #80
        sta $D05C // Side border width LSB

        // point VIC-IV to bottom 16KB of display memory
        //
        lda #$ff
        sta $DD01
        sta $DD00

        // We use VIC-II style registers as this resets video frame in
        // least instructions, and 40 columns is fine for us.
        //
        lda #$14        // 0001 0100
        sta $D018        // VIC-II Character/Screen location

        lda #$1B        // 0001 1011
        sta $D011        // VIC-II Control Register

        lda #$C8        // 1100 1000
        sta $D016        // VIC-II Control Register

        // Now switch to 16-bit text mode so that we can use proportional
        // characters and full-colour characters for chars >$FF for the logo
        //
        lda #$c5
        lda $d054        // VIC-IV Control Register C

        // and 80 bytes (40 16-bit characters) per row.
        //
        lda #<80
        sta $d058
        lda #>80
        sta $d059

        rts

//         ========================

resetpalette:
        // reset VIC-IV palette to sensible defaults.
        // load C64 colours into palette bank 3 for use when
        // PAL bit in $D030 is set.
        //
        lda #$04
        tsb $D030        // enable PAL bit in $D030

        lda #$ff
        sta $D070        // select palette bank 3 for display and edit

        // C64 colours designed to look like C65 colours on an
        // RGBI screen.
        //
        // formatted in ASM to help visualise what each code is for.
        //
        lda #$00
            sta $D100
            sta $D200
            sta $D300

        lda #$ff
            sta $D101
            sta $D201
            sta $D301

        lda #$ba
                    sta $D102
                lda #$13
                    sta $D202
                lda #$62
                    sta $D302

                lda #$66
                    sta $D103
                lda #$ad
                    sta $D203
                lda #$ff
                    sta $D303

                lda #$bb
                    sta $D104
                lda #$f3
                    sta $D204
                lda #$8b
                    sta $D304

                lda #$55
                    sta $D105
                lda #$ec
                    sta $D205
                lda #$85
                    sta $D305

                lda #$d1
                    sta $D106
                lda #$e0
                    sta $D206
                lda #$79
                    sta $D306

                lda #$ae
                    sta $D107
                lda #$5f
                    sta $D207
                lda #$c7
                    sta $D307

                lda #$9b
                    sta $D108
                lda #$47
                    sta $D208
                lda #$81
                    sta $D308

                lda #$87
                    sta $D109
                lda #$37
                    sta $D209
                lda #$00
                    sta $D309

                lda #$dd
                    sta $D10a
                lda #$39
                    sta $D20a
                lda #$78
                    sta $D30a

                lda #$b5
                    sta $D10b
                    sta $D20b
                    sta $D30b

                lda #$b8
                    sta $D10c
                    sta $D20c
                    sta $D30c

                lda #$0b
                    sta $D10d
                lda #$4f
                    sta $D20d
                lda #$ca
                    sta $D30d

                lda #$aa
                    sta $D10e
                lda #$d9
                    sta $D20e
                lda #$fe
                    sta $D30e

                lda #$8b
                    sta $D10f
                    sta $D20f
                    sta $D30f


    rts

//         ========================

// erase standard 40-column screen
//
erasescreen:
        // bank in 2nd KB of colour RAM
        //
        lda #$01
        tsb $D030

        // use DMA to clear screen and colour RAM
        // The screen is in 16-bit bit mode, so we actually need to fill
        // with $20,$00, ...
        //
        // We will cheat by setting the first four bytes, and then copying from
        // there, and it will then read from the freshly written bytes.
        // (two bytes might not be enough to allow the write from the last DMA
        //  action to be avaialble for reading because of how the DMAgic is
        //  pipelined).
        //
        lda #$20
        sta $0400
        sta $0402
        lda #$00
        sta $0401
        sta $0403

        // Set bottom 22 bits of DMA list address as for C65
        // (8MB address range)
        //
        lda #$ff
        sta $d702

        // Hyppo ROM is at $FFFE000 - $FFFFFFF, so
        // we need to tell DMAgic that DMA list is in $FFxxxxx.
        // this has to be done AFTER writing to $d702, as $d702
        // clears bits 27 - 22 of the DMA list address to help with
        // compatibility.
        //
        lda #$ff
        sta $d704

        lda #>erasescreendmalist
        sta $d701

        // set bottom 8 bits of address and trigger DMA.
        //
        lda #<erasescreendmalist
        sta $d705

        // bank 2nd KB of colour RAM back out
        //
        lda #$01
        trb $D030

//         ========================

        // move cursor back to top of the screen
        // (but leave 8 rows for logo and banner text)
        //
        lda #$08
        sta screenrow

        // draw 40x8 char block for banner
        //
        ldy #$00
        lda #$00
logo1:
        sta $0400,y
        inc_a
        iny
        iny
        bne logo1
logo1a:
        sta $0500,y
        inc_a
        iny
        iny
        bne logo1a
logo1b:
        sta $0600,y
        inc_a
        iny
        iny
        cpy #$80
        bne logo1b

        // then write the high bytes for these (all $01, so char range will be
        // $100-$140. $100 x $40 = $4000-$4FFF
        //
        ldx #$00
        lda #$16     // $1600 x $40 = $58000 where banner tiles sit
logo2:
        sta $0401,x
        inc_a
        sta $0581,x
        dec_a
        sta $0501,x
        inx
        inx
        bne logo2

        // finally set palette for banner using contents of memory at $57D00-$57FFF
setbannerpalette:
        // Set DMA list address
        //
        lda #>bannerpalettedmalist
        sta $d701
        lda #$0f
        sta $d702 // DMA list address is $xxFxxxx
        lda #$ff
        sta $d704 // DMA list address is $FFxxxxx

        // set bottom bits of DMA list address and trigger enhanced DMA
        //
        lda #<bannerpalettedmalist
        sta $d705

        rts

bannerpalettedmalist:
        // MEGA65 enhanced DMA options
        .byte $0A      // Request format is F018A
        .byte $80,$00,$81,$FF // src = $00xxxxx, dst=$FFxxxxx
        .byte $00 // no more options
        // F018A DMA list
        .byte $00   // COPY + no chained request
        .word $0300
        .word $7D00 //
        .byte $05   // source bank 05
        .word $3100 // ; $xxx3100
        .byte $0D   // ; $xxDxxxx
        .word $0000 // modulo (unused)



//         ========================

erasescreendmalist:
        // Clear screen RAM
        //
        // MEGA65 enhanced DMA options
        .byte $0A      // Request format is F018A
        .byte $00 // no more options
        // F018A DMA list
        .byte $04   // COPY + chained request
        .word 1996  // 40x25x2-4 = 1996
        .word $0400 // copy from start of screen at $0400
        .byte $00   // source bank 00
        .word $0404 // ... to screen at $0402
        .byte $00   // screen is in bank $00
        .word $0000 // modulo (unused)

        // Clear colour RAM
        //
        // MEGA65 DMA options
        .byte $81,$FF // Destination is $FFxxxxx
        .byte $00     // no more options
        // F018A dma list
        .byte $03     // FILL + no more chained requests
        .word 2000    // 40x25x2 = 2000
        .byte $01     // fill with white = $01
        .byte $00,$00 // rest of source address is ignored in fill
        .word $0000   // destination address
        .byte $08     // destination bank
        .word $0000   // modulo (unused)


//         ========================

printmessage:        // HELPER routine
        //
        // This subroutine takes inputs from the X and Y registers,
        // so set these registers before calling this subroutine,
        // The X and Y registers need to point to a message as shown below:
        //
        //         ldx #<msg_foundsdcard
        //         ldy #>msg_foundsdcard
        //         jsr printmessage
        //
        // Ie: the X is the high-byte of the 16-bit address, and
        //     the Y is the low-byte  of the 16-bit address.

        stx <zptempp        // zptempp is 16-bit pointer to message
        sty <zptempp+1

        lda #$00
        sta <zptempp2        // zptempp2 is 16-bit pointer to screen
        lda #$04
        sta <zptempp2+1

        ldx screenrow

        // Makesure we can't accidentally write on row zero
        bne pm22
        ldx #$08
pm22:

        // if we have reached the bottom of the screen, start writing again
        // from the top of the screen (but don't touch the top 8 rows for
        // logo and banner)
        cpx #25
        bne pm2
        ldx #$08
        stx screenrow

        // work out the screen address
        //
pm2:    cpx #$00
        beq pm1
        clc
        lda <zptempp2
        adc #$50          // 40 columns x 16 bit
        sta <zptempp2
        lda <zptempp2+1
        adc #$00
        sta <zptempp2+1

        // if reached bottom of screen, then loop back to top of screen
        //
        cmp #$0b
        bcc pm5
        lda <zptempp2
        cmp #$d0
        bcc pm5

        lda #$80
        sta <zptempp2
        lda #$06
        sta <zptempp2+1
pm5:    dex
        bne pm2
pm1:

        // Clear line (16-bit chars, so write #$0020 to each word
        //
        ldy #$00
pm1b:   lda #$20
        sta (<zptempp2),y
        iny
        lda #$00
        sta (<zptempp2),y
        iny
        cpy #$50
        bne pm1b

writestring:
        phz
        ldy #$00
        ldz #$00
pm3:    lda (<zptempp),y
        beq endofmessage

        // convert ASCII/PETSCII to screen codes
        //
        cmp #$40
        bcc pm4
        and #$1f

pm4:                // write 16-bit character code
        //
        sta_bp_z(<zptempp2)
        inz
        pha
        lda #$00
        sta_bp_z(<zptempp2)
        pla
        iny
        inz
        bne pm3
endofmessage:
        inc screenrow

        plz
        rts

//         ========================

printbanner:
        stx <zptempp
        sty <zptempp+1
        lda #<$0504
        sta zptempp2
        lda #>$0504
        sta zptempp2+1
        jsr writestring
        dec screenrow
        rts

//         ========================

printhex:
        // helper function
        //
        // seems to want to print the value if the z-reg onto the previous line written to the screen,
        // so currently the screen consists of say "mounted $$ images"
        // and this routine will go and change the "$$" to the value in the z-reg
        //
        // BG: surely this can be replaced with updating the "$$" before printing the string
        //
        // INPUT: .Y, BG seems to be an offset, should be set to zero?
        // INPUT: .Z, value in Z-reg to be displayed omn the screen
        //
        tza
        lsr
        lsr
        lsr
        lsr
        jsr printhexdigit
        tza
        and #$0f
printhexdigit:
        // find next $ sign to replace with hex digit
        //
        tax
phd3:   lda (<zptempp2),y
        cmp #$24
        beq phd2
        iny
        iny
        cpy #$50
        bne phd3
        rts

phd2:   txa
        ora #$30
        cmp #$3a
        bcc phd1
        sbc #$39
phd1:   sta (<zptempp2),y
        iny
        iny
        rts

//         ========================

go64:

// Transfer control to C64 kernel.
// (This also allows entry to C65 mode, because the
//  C64-mode kernel on the C65 checks if C65 mode
//  should be entered.)

        // Check if hold boot switch is set (control-key)
        //
l41:    lda buckykey_status
        and #$14
        beq l42      // no, so continue

        // yes, display message
        //
        ldx #<msg_releasectrl
        ldy #>msg_releasectrl
        jsr printmessage

l41a:
        // check for ALT key to jump to utility menu
        jsr utility_menu_check

        // and otherwise wait until CTRL is released
        lda buckykey_status
        and #$04
        bne l41a
l42:
        // unmap sector buffer so C64 can see CIAs
        //
        lda #$82
        sta sd_ctrl

        // copy routine to stack to switch to
        // C64 memory map and enter via reset
        // vector.

        // erase hyppo ROM copy from RAM
        // (well, at least enough so that BASIC doesn't get upset)
        // XXX - use DMA
        //
        ldx #$00
        txa
g61:    sta $0800,x
        inx
        bne g61

        // reset video mode to normal
        // and return CPU to slow speed for exit
        lda #$00
        sta $d054

        lda #<40
        sta $d058
        lda #>40
        sta $d059

        // write protect ROM RAM
        lda #$04
        tsb hypervisor_feature_enables

        jsr task_set_c64_memorymap
        jsr task_set_pc_to_reset_vector
        jsr task_dummy_nmi_vector

        // This must happen last, so that the ultimax cartridge
        // reset vector is used, instead of the one in the loaded ROM
        jsr setup_for_ultimax_cartridge

        // Apply RESET to cartridge for a little while so that cartridges
        // with capacitors tied to EXROM or GAME are visible.
        // Do this last, because some cartridges remain visible for as little
        // as 512 usec.
        jsr reset_cartridge

        // exit from hypervisor to start machine
        sta hypervisor_enterexit_trigger

#import "ultimax.asm"

//         ========================

// BG: the longpeek subroutine does not get called from hyppo,
//     it gets called only from the hyppo_task file,
//     so i suggest moving this subroutine to that file.

longpeek:
        // Use DMAgic to read any byte of RAM in 28bit address space.
        // Value gets read into $BC00 (hyppo_scratchbyte0)
        // ($FFFBC00 - $FFFBDFF)

        // Patch DMA list
        //
        stx longpeekdmalist_src_lsb
        sty longpeekdmalist_src_2sb
        stz longpeekdmalist_src_msb
        sta longpeekdmalist_src_mb

        // Set DMA list address
        //
        lda #>longpeekdmalist
        sta $d701
        lda #$0f
        sta $d702 // DMA list address is $xxFxxxx
        lda #$ff
        sta $d704 // DMA list address is $FFxxxxx

        // set bottom bits of DMA list address and trigger enhanced DMA
        //
        lda #<longpeekdmalist
        sta $d705
        rts

longpeekdmalist:
        // MEGA65 Enhanced DMA options
        .byte $0A      // Request format is F018A
        .byte $80
longpeekdmalist_src_mb:
        .byte $FF
        .byte $81,$FF // destination is always $FFxxxxx
        .byte $00 // end of options marker
        // F018A format request follows
        .byte $00 // COPY, no chain
        // 1 byte
        .word $0001
        // source address
longpeekdmalist_src_lsb:
        .byte $00
longpeekdmalist_src_2sb:
        .byte $00
longpeekdmalist_src_msb:
        .byte $00
        // destination address ($xxFBC00)
        .word hyppo_scratchbyte0
        .byte $0F
        .byte $00,00 // Modulo

longpoke:
        // Use DMAgic to write any byte of RAM in C65 1MB address space.
        // A = value
        // X = Address LSB
        // Y = Address MidB
        // Z = Address Bank

        // Patch DMA list
        //
        sta longpokevalue
        stx longpokeaddress+0
        sty longpokeaddress+1
        stz longpokeaddress+2
        tza
        lsr
        lsr
        lsr
        lsr
        sta longpokedmalist_dest_mb // DMAgic destination MB
        // and enable F108B enhanced mode by default
        lda #$01
        sta $d703

        // Set DMA list address
        //
        lda #>longpokedmalist
        sta $d701
        lda #$0f
        sta $d702 // DMA list address is $xxFxxxx
        lda #$ff
        sta $d704 // DMA list address is $FFxxxxx

        // set bottom bits of DMA list address and trigger enhhanced DMA
        //

        lda #<longpokedmalist
        sta $d705
        rts

longpokedmalist:
        // MEGA65 Enhanced DMA option list
        .byte $0A      // Request format is F018A
        .byte $81
longpokedmalist_dest_mb:
        .byte $00
        .byte $00 // no more enhanced DMA options
        // F018A dma list
        .byte $03 // FILL, no chain
        // 1 byte
        .word $0001
        // source address (LSB = fill value)
longpokevalue:
        .byte $00
        .word $0000
        // destination address
longpokeaddress:
        .word $0000
        .byte $0F
        .byte $00,00 // Modulo


//         ========================

// reset memory map to default
resetmemmap:
        // clear memory MAP MB offset register
        //
        lda #$00
        ldx #$0f
        ldy #$00   // keep hyppo mapped at $8000-$BFFF
        ldz #$3f

        map

        // and clear all mapping
        //
        tax
        ldy #$00   // keep hyppo mapped at $8000-$BFFF
        ldz #$3f

        map
        eom

        rts

//         ========================

enhanced_io:

        // If C=1, enable enhanced IO bank,
        //   else, return to C64 standard IO map.
        //

        bcs l1
        // Return to VIC-II / C64 IO
        //
        lda #$00
        sta viciv_magic
        rts

l1:                // Enable VIC-IV / MEGA65 IO
        //
        lda #$47
        sta viciv_magic
        lda #$53
        sta viciv_magic
        rts


//         ========================
#import "keyboard.asm"

utility_menu_check:
        lda buckykey_status
        cmp #$03
        beq @startUtilMenu
        and #$10
        bne @startUtilMenu
        rts
@startUtilMenu:
        jmp utility_menu

keyboardread:

// Check for keyboard activity, and change which ROM we intend to read
// based on that, i.e., holding any key down during boot will load MEGA65<that character>.ROM instead of MEGA65.ROM

        jsr utility_menu_check

        jsr scankeyboard
        bcs kr2  // if an error occured
        cmp #$20
        bne @notUtilMenu
        jmp utility_menu
@notUtilMenu:
        cmp #$30
        bcc kr2
        cmp #$39
        bcs kr2
kr2:        lda #$20 // default to space
kr1:
        // put character into 6th byte position of ROM file name.
        // so no key looks for MEGA65.ROM, where as 0-9 will look
        // for MEGA65x.ROM, where x is the number.
        ldx #6
        cmp #$20
        beq default_rom
        sta txt_MEGA65ROM,x
        inx
default_rom:
        lda #'.'
        sta txt_MEGA65ROM,x
        inx
        lda #'R'
        sta txt_MEGA65ROM,x
        inx
        lda #'O'
        sta txt_MEGA65ROM,x
        inx
        lda #'M'
        sta txt_MEGA65ROM,x
        inx
        lda #0
        sta txt_MEGA65ROM,x

        rts

//         ========================

hypervisor_nmi:
hypervisor_irq:
        // Default interrupt handlers for hypervisor: for now just mask the
        // interrupt source.  Later we can have raster splits in the boot
        // display if we so choose.
        sei
        rti

hypervisor_setup_copy_region:
        // Hypervisor copy region sit entirely within the first 32KB of
        // mapped address space. Since we allow a 256 byte copy region,
        // we limit the start address to the range $0000-$7EFF
        // XXX - We should also return an error if there is an IO
        // region mapped there, so that the hypervisor can't be tricked
        // into doing privileged IO operations as part of the copy-back

        lda hypervisor_y
        bmi hscr1
        cmp #$7f
        beq hscr1
        sta hypervisor_userspace_copy_vector +1
        lda #$00
        sta hypervisor_userspace_copy_vector +0

        Checkpoint("hypervisor_setup_copy_region <success>")

        sec
        rts

hscr1:
        Checkpoint("hypervisor_setup_copy_region <failure>")

        lda #dos_errorcode_invalid_address
        jmp dos_return_error

//         ========================

checkpoint:

        // Routine to record the progress of code through the hypervisor for
        // debugging problems in the hypervisor.
        // If the JSR checkpoint is followed by $00, then a text string describing the
        // checkpoint is inserted into the checkpoint log.
        // Checkpoint data is recorded in the 2nd 16KB of colour RAM.

        // Save all registers and CPU flags
        sta checkpoint_a
        stx checkpoint_x
        sty checkpoint_y
        stz checkpoint_z
        php
        pla
        sta checkpoint_p

        // pull PC return address from stack
        // (JSR pushes return_address-1, so add one)
        pla
        clc
        adc #$01
        sta checkpoint_pcl
        pla
        adc #$00
        sta checkpoint_pch

        // Only do checkpoints visibly if shift held during boot
        lda buckykey_status
        and #$03
        beq cp9

        // Write checkpoint byte values out as hex into message template
        ldx checkpoint_a
        jsr checkpoint_bytetohex
        sty msg_checkpoint_a+0
        stx msg_checkpoint_a+1

        ldx checkpoint_x
        jsr checkpoint_bytetohex
        sty msg_checkpoint_x+0
        stx msg_checkpoint_x+1

        ldx checkpoint_y
        jsr checkpoint_bytetohex
        sty msg_checkpoint_y+0
        stx msg_checkpoint_y+1

        ldx checkpoint_z
        jsr checkpoint_bytetohex
        sty msg_checkpoint_z+0
        stx msg_checkpoint_z+1

        ldx checkpoint_p
        jsr checkpoint_bytetohex
        sty msg_checkpoint_p+0
        stx msg_checkpoint_p+1

        ldx checkpoint_pch
        jsr checkpoint_bytetohex
        sty msg_checkpoint_pc+0
        stx msg_checkpoint_pc+1

        ldx checkpoint_pcl
        jsr checkpoint_bytetohex
        sty msg_checkpoint_pc+2
        stx msg_checkpoint_pc+3

        // Clear out checkpoint message
        ldx #59
        lda #$20
cp4:    sta msg_checkpointmsg,x
        dex
        bpl cp4
cp9:
        // Read next byte following the return address to see if it is $00,
        // if so, then also store the $00-terminated text message that follows.
        // e.g.:
        //
        // jsr checkpoint
        // .byte 0,"OPEN DIRECTORY",0
        //
        // to record a checkpoint with the string "OPEN DIRECTORY"

        ldy #$00
        lda (<checkpoint_pcl),y

        bne nocheckpointmessage

        // Copy null-terminated checkpoint string
        ldx #$00
        iny
cp3:    lda (<checkpoint_pcl),y
        beq endofcheckpointmessage
        sta msg_checkpointmsg,x
        inx
        iny
        cpy #60
        bne cp3

        // flush out any excess bytes at end of message
cp44:   lda (<checkpoint_pcl),y
        beq endofcheckpointmessage
        iny
        bra cp44

endofcheckpointmessage:
        // Skip $00 at end of message
        iny

nocheckpointmessage:

        // Advance return address following any checkpoint message
        tya
        clc
        adc checkpoint_pcl
        sta checkpoint_pcl
        lda checkpoint_pch
        adc #$00
        sta checkpoint_pch

        // Only do checkpoints visibly if shift key held
        lda buckykey_status
        and #$03
        beq checkpoint_return

        // output checkpoint message to serial monitor
        ldx #0
        // do not adjust x-reg until label "checkpoint_return"
cp5:
        // wait for uart to be not busy
        lda hypervisor_write_char_to_serial_monitor        // LSB is busy status
        bne cp5                // branch if busy (LSB=1)

        // uart is not busy, so write the char
        lda msg_checkpoint,x
        sta hypervisor_write_char_to_serial_monitor
        inx

        cmp #10                // compare A-reg with "LineFeed"
        bne cp5

checkpoint_return:
        // restore registers
        lda checkpoint_p
        php
        lda checkpoint_a
        ldx checkpoint_x
        ldy checkpoint_y
        ldz checkpoint_z
        plp

        // return by jumping to the
        jmp (checkpoint_pcl)

//         ========================

checkpoint_bytetohex:

        // BG: this is a helper function to convert a HEX-byte to
        //     its equivalent two-byte char representation
        //
        //     input ".X", containing a HEX-byte to convert
        //   outputs ".X" & ".Y", Y is MSB, X is LSB, print YX
        txa
        and #$f0
        lsr
        lsr
        lsr
        lsr
        jsr checkpoint_nybltohex
        tay
        txa
        and #$0f
        jsr checkpoint_nybltohex
        tax
        rts

//         ========================

checkpoint_nybltohex:

        and #$0f
        ora #$30
        cmp #$3a
        bcs cpnth1
        rts

cpnth1: adc #$06
        rts

//         ========================
//       Scan the 32KB colour RAM looking for pre-loaded utilities.
//       Offer for the user to be able to launch one of them

utility_menu:
        // Display GIT commit again, so that it's easy to check commit of a build
        ldx #<msg_gitcommit
        ldy #>msg_gitcommit
        jsr printmessage

	// Display utility menu message
	ldx #<msg_utilitymenu
        ldy #>msg_utilitymenu
        jsr printmessage

        // First utility will be number 1
        lda #$30
        sta zptempv

        jsr utillist_rewind
um1:
        jsr utillist_validity_check
        bcc utility_end_of_list

        // Display utility and assign number
        ldy #39
        lda #$20
um2:    sta msg_utility_item,y
        dey
        cpy #2
        bne um2
        iny
        inc zptempv
        lda zptempv
        sta msg_utility_item
        ldz #4
um4:    nop
        lda_bp_z(<zptempv32)
        sta msg_utility_item,y
        beq um3
        iny
        inz
        bra um4
um3:    ldx #<msg_utility_item
        ldy #>msg_utility_item
        jsr printmessage

        jsr utillist_next

        bra um1


utility_end_of_list:
        // XXX Get input from user (accept only numbers 1 - 9)
        jsr scankeyboard
        cmp #$ff
        beq utility_end_of_list
        cmp #$31
        bcc utility_end_of_list
        cmp #$39
        bcs utility_end_of_list

        // XXX Based on input, find that utility
        and #$f
        tax
        dex // input is 1-9, so subtract one for list beginning at 0
        jsr utillist_rewind
ueol2:  jsr utillist_validity_check
        // Select again if first choice invalid
        bcc utility_end_of_list
        dex
        bmi ueol1
        jsr utillist_next
        bra ueol2
ueol1:

        inc $d021

        // XXX - Set hardware protection bits based on utility definition
        //       (and check that utility memory has not been modified. If modified.
        //        give an error instead of giving privileges, so that there is no
        //        privilege escalation vulnerability here.)
        // XXX - In fact, if the utility memory has been modified, we shouldn't even
        //       offer the menu at all perhaps?

        // Load selected utility into memory
        // length @ offset 36
        ldz #36
        nop
        lda_bp_z(<zptempv32)
        sta utility_dmalist_length+0
        inz
        nop
        lda_bp_z(<zptempv32)
        sta utility_dmalist_length+1
        lda <zptempv32+0
        clc
        adc #44 // length of header structure
        sta utility_dmalist_srcaddr+0
        lda <zptempv32+1
        adc #0
        sta utility_dmalist_srcaddr+1

        // load address is always $07FF (to skip $0801 header)
        // start @ zptempv32 + 44
        // DMA list is from Hypervisor ROM, so DMA list address MB also = $FF
        lda #$ff
        sta $d702
        sta $d704
        lda #>utility_dmalist
        sta $d701
        lda #<utility_dmalist
        sta $d705       // Trigger enhanced DMA

        // clear 16-bit char mode
        lda #$05        // 0000 0101
        trb $d054       // VIC-IV Control Register C

        // and 40 bytes (40 8-bit characters) per row.
        lda #<40
        sta $d058
        lda #>40
        sta $d059

        // screen at $0800 for debug
        lda #$25
        sta $d018

        // Exit hypervisor, with PC set to entry point of utility
        ldz #38
        nop
        lda_bp_z(<zptempv32)
        sta hypervisor_pcl
        inz
        nop
        lda_bp_z(<zptempv32)
        sta hypervisor_pch

        jsr task_set_c64_memorymap
        lda #$3f
        sta hypervisor_cpuport00
        lda #$35 // IO + Kernel ROM @ $E000 (although Kernel is blank)
        sta hypervisor_cpuport01

        // make $FFD2 safe for CC65 compiled programs that call
        // there to set lower case during initialisation.
        // We need to write $60 to $2FFD2
        lda #$60 // RTS
        ldx #$d2
        ldy #$ff
        ldz #$02
        jsr longpoke

        // Next instruction exits hypervisor to user mode
        sta hypervisor_enterexit_trigger

utility_dmalist:
        // copy $FF8xxxx-$FF8yyyy to $00007FF-$000xxxx

        // MEGA65 Enhanced DMA options
        .byte $0A      // Request format is F018A
        .byte $80,$FF  // Copy from $FFxxxxx
        .byte $81,$00  // Copy to $00xxxxx
        .byte $00 // no more options
        // F018A DMA list
        .byte $00 // copy + last request in chain
utility_dmalist_length:
        .word $FFFF // size of copy  (gets overwritten)
utility_dmalist_srcaddr:
        .word $FFFF // starting addr (gets overwritten)
        .byte $08   // of bank $8
        .word $07FF // destination address is $0801 - 2
        .byte $00   // of bank $0
        .word $0000 // modulo (unused)


msg_utility_item:
        .text "1. 32 CHARACTERS OF UTILITY NAME...    "
        .byte 0

utillist_next:

        // Advance pointer to the next pointer
        ldz #42
        nop
        lda_bp_z(<zptempv32)
        phx
        tax
        inz
        nop
        lda_bp_z(<zptempv32)
        // XXX - Make sure it can't point earlier into the colour RAM here

        sta <zptempv32+1
        stx <zptempv32
        plx
        rts

utillist_validity_check:
        // See if this is a valid utility entry
        ldz #0

        // Check for magic value
        nop // 32-bit pointer access follows
        lda_bp_z(<zptempv32)
        cmp #'M'
        bne ulvc_fail
        inz
        nop // 32-bit pointer access follows
        lda_bp_z(<zptempv32)
        cmp #'6'
        bne ulvc_fail
        inz
        nop // 32-bit pointer access follows
        lda_bp_z(<zptempv32)
        cmp #'5'
        bne ulvc_fail
        inz
        nop // 32-bit pointer access follows
        lda_bp_z(<zptempv32)
        cmp #'U'
        bne ulvc_fail

        // Check self address
        ldz #40
        nop // 32-bit pointer access follows
        lda_bp_z(<zptempv32)
        cmp zptempv32
        bne ulvc_fail
        inz
        nop // 32-bit pointer access follows
        lda_bp_z(<zptempv32)
        cmp zptempv32+1
        bne ulvc_fail

        // success
        sec
        rts

ulvc_fail:
        clc
        rts

utillist_rewind:
        // Set pointer to first entry in colour RAM ($0850)
        lda #<$0850
        sta <zptempv32
        lda #>$0850
        sta <zptempv32+1
        lda #<$0FF8
        sta <zptempv32+2
        lda #>$0FF8
        sta <zptempv32+3

        rts

msg_utilitymenu:
        .text "SELECT UTILITY TO LAUNCH"
        .byte 0

serialwrite:
        // write character to serial port
        // XXX - Have some kind of permission control on this
        // XXX - $D67C should not work when matrix mode is enabled at all?
        sta hypervisor_write_char_to_serial_monitor
        sta hypervisor_enterexit_trigger

//         ========================

// checkpoint message

msg_checkpoint:         .text "$"
msg_checkpoint_pc:      .text "%%%% A:"
msg_checkpoint_a:       .text "%%, X:"
msg_checkpoint_x:       .text "%%, Y:"
msg_checkpoint_y:       .text "%%, Z:"
msg_checkpoint_z:       .text "%%, P:"
msg_checkpoint_p:       .text "%% :"
msg_checkpointmsg:      .text "                                                             " // END_OF_STRING
                        .byte 13,10  // CR/LF

//         ========================

msg_checkpoint_eom:

// messages all have to be <=40 bytes long

msg_retryreadmbr:       .text "RE-TRYING TO READ MBR"
                        .byte 0
msg_hyppo:              .text "MEGA65 MEGAOS HYPERVISOR V00.12"
                        .byte 0
msg_hyppohelp:          .text "ALT=UTIL MENU CTRL=HOLD-BOOT SHIFT=DEBUG"
                        .byte 0
msg_romok:              .text "ROM CHECKSUM OK - BOOTING"
                        .byte 0
// msg_rombad:          .text "ROM CHECKSUM FAIL - LOADING ROMS"
//                      .byte 0
// msg_charrombad:      .text "COULD NOT LOAD CHARROM.M65"
//                      .byte 0
msg_charromloaded:      .text "LOADED CHARROM.M65 ($$$$ PAGES)"
                        .byte 0
msg_megaromloaded:      .text "LOADED MEGA65ROM.M65 ($$$$ PAGES)"
                        .byte 0
msg_tryingsdcard:       .text "LOOKING FOR SDHC CARD >=4GB..."
                        .byte 0
msg_foundsdcard:        .text "SD CARD IS NOT SDHC. REPLACE WITH SDHC CARD."
                        .byte 0
msg_foundsdhccard:      .text "FOUND AND RESET SDHC CARD"
                        .byte 0
msg_sdcarderror:        .text "ERROR READING FROM SD CARD"
                        .byte 0
msg_sdredoread:         .text "RE-READING SDCARD"
                        .byte 0
msg_nosdcard:           .text "NO SDCARD, TRYING BUILT-IN ROM"
                        .byte 0
msg_badformat:          .text "BAD MBR OR DOS BOOT SECTOR."
                        .byte 0
msg_sdcardfound:        .text "READ PARTITION TABLE FROM SDCARD"
                        .byte 0
msg_foundromfile:       .text "FOUND ROM FILE. START CLUSTER = $$$$$$$$"
                        .byte 0
msg_diskcount:          .text "DISK-COUNT=$$, DEFAULT-DISK=$$"
                        .byte 0
// msg_diskdata0:       .text "DISK-TABLE:"
//                      .byte 0
// msg_diskdata:        .text "BB$$:$$.$$.$$.$$.$$.$$.$$.$$"
//                      .byte 0
msg_filelengths:        .text "LOOKING FOR $$ BYTES, I SEE $$ BYTES"
                        .byte 0
msg_fileopenerror:      .text "COULD NOT OPEN ROM FILE FOR READING"
                        .byte 0
msg_readingfile:        .text "READING ROM FILE..."
                        .byte 0
msg_romfilelongerror:   .text "ROM TOO LONG: (READ $$$$ PAGES)"
                        .byte 0
msg_romfileshorterror:  .text "ROM TOO SHORT: (READ $$$$ PAGES)"
                        .byte 0
msg_clusternumber:      .text "CURRENT CLUSTER=$$$$$$$$"
                        .byte 0
msg_sectoraddress:      .text "CURRENT SECTOR= $$$$$$$$"
                        .byte 0
msg_nod81:              .text "CANNOT MOUNT MEGA65.D81 - (ERRNO: $$)"
                        .byte 0
msg_d81mounted:         .text "MEGA65.D81 SUCCESSFULLY MOUNTED"
                        .byte 0
msg_releasectrl:        .text "RELEASE CONTROL TO CONTINUE BOOTING."
                        .byte 0
msg_romnotfound:        .text "COULD NOT FIND ROM MEGA65XXROM"
                        .byte 0
msg_foundhickup:        .text "LOADING HICKUP.M65 INTO HYPERVISOR"
                        .byte 0
msg_no1541rom:          .text "COULD NOT LOAD 1541ROM.M65"
                        .byte 0
// msg_nohickup:        .text "NO HICKUP.M65 TO LOAD (OR BROKEN)"
//                      .byte 0
// msg_hickuploaded:    .text "HICKUP LOADED TO 00004000 - $$$$$$$$"
//                      .byte 0
msg_alreadyhicked:      .text "RUNNING HICKED HYPERVISOR"
                        .byte 0
msg_lookingfornextsector:
                        .text "LOOKING FOR NEXT SECTOR OF FILE"
                        .byte 0
msg_nologo:             .text "COULD NOT LOAD BANNER.M65 (ERRNO:$$)"
                        .byte 0
msg_cdrootfailed:       .text "COULD NOT CHDIR TO / (ERRNO:$$)"
                        .byte 0
msg_tryingcard1:        .text "TRYING SDCARD BUS 1"
                        .byte 0
msg_usingcard0:         .text "USING SDCARD BUS 0"
                        .byte 0
msg_dmagica:            .text "DMAGIC REV A MODE"
                        .byte 0
msg_dmagicb:            .text "DMAGIC REV B MODE"
                        .byte 0

// Include the GIT Message as a string
#import "../version.asm"

msg_blankline:          .byte 0

//         ========================
            // filename of 1541 ROM
txt_1541ROM:            .text "1541ROM.M65"
                        .byte 0

            // filename of character ROM
txt_CHARROMM65:         .text "CHARROM.M65"
                        .byte 0

            // filename of ROM we want to load in FAT directory format
            // (the two zero bytes are so that we can insert an extra digit after
            // the 5, when a user presses a key, so that they can choose a
            // different ROM to load).
            //
txt_MEGA65ROM:          .text "MEGA65.ROM"
                        .byte 0,0

            // filename of 1581 disk image we mount by default
            //
txt_MEGA65D81:          .text "MEGA65.D81"
                        .byte 0,0,0,0,0,0,0

            // filename of hyppo update file
            //
txt_HICKUPM65:          .text "HICKUP.M65"
                        .byte 0

            // filename containing boot logo
            //
txt_BOOTLOGOM65:        .text "BANNER.M65"
                        .byte 0

            // filename containing freeze menu
txt_FREEZER:            .text "FREEZER.M65"
                        .byte 0

            // If this file is present, then machine starts up with video
            // mode set to NTSC (60Hz), else as PAL (50Hz).
            // This is to allow us to boot in PAL by default, except for
            // those who have a monitor that cannot do 50Hz.
txt_NTSC:               .text "NTSC"
                        .byte 0

//         ========================

#import "debug.asm"

//         ========================

        // Table of available disks.
        // Include native FAT32 disks, as well as (in the future at least)
        // mounted .D41, .D71, .D81 and .DHD files using Commodore DOS filesystems.
        // But for now, we are supporting only FAT32 as the filesystem.
        // See hyppo_dos.asm for information on how the table is used.
        // Entries are 32 bytes long, so we can have 6 of them.
        //
        .label dos_max_disks = 6

        .segment DOSDiskTable
        * = DOSDiskTable_Start
dos_disk_table:

        .segment SysPartStructure
        * = SysPartStructure_Start

syspart_structure:

syspart_start_sector:
        .byte 0,0,0,0
syspart_size_in_sectors:
        .byte 0,0,0,0
syspart_reserved:
        .byte 0,0,0,0,0,0,0,0

// For fast freezing/unfreezing, we have a number of contiguous
// freeze slots that can each store the state of the machine
// We note where the area begins, how big it is, how many slots
// it has, and how many sectors are used at the start of the area
// to hold a directory with 128 bytes per slot, the contains info
// about the frozen program.
syspart_freeze_area_start:
        .byte 0,0,0,0
syspart_freeze_area_size_in_sectors:
        .byte 0,0,0,0
syspart_freeze_slot_size_in_sectors:
        .byte 0,0,0,0
syspart_freeze_slot_count:
        .byte 0,0
syspart_freeze_directory_sector_count:
        .byte 0,0

        // The first 64 freeze slots are reserved for various purposes
        .label syspart_freeze_slots_reserved  = 64
        // Freeze slot 0 is used when the hypervisor needs to
        // temporarily shove all or part of the active process out
        // the way to do something
        .label freeze_slot_temporary = 0

        // Freeze slots 1 - 63 are currently reserved
        // They will likely get used for a service call-stack
        // among other purposes.

        // We then have a similar area for system services, which are stored
        // using much the same representation, but are used as helper
        // programs.
syspart_service_area_start:
        .byte 0,0,0,0
syspart_service_area_size_in_bytes:
        .byte 0,0,0,0
syspart_service_slot_size_in_bytes:
        .byte 0,0,0,0
syspart_service_slot_count:
        .byte 0,0
syspart_service_directory_sector_count:
        .byte 0,0

/*  -------------------------------------------------------------------
    Hypervisor DOS work area and scratch pad at $BC00-$BCFF
    ---------------------------------------------------------------- */

        .segment DOSWorkArea
        * = DOSWorkArea_Start

hyppo_scratchbyte0:
        .byte $00

        // The number of disks we have
        //
dos_disk_count:
        .byte $00

        // The default disk
        //
dos_default_disk:
        .byte $00

        // The current disk
        //
dos_disk_current_disk:
        .byte $00

        // Offset of current disk entry in disk table
        //
dos_disk_table_offset:
        .byte $00

        // cluster of current directory of current disk
        //
dos_disk_cwd_cluster:
        .byte 0,0,0,0

//         ========================

        // Current point in open directory
        //
dos_opendir_cluster:
        .byte 0,0,0,0
dos_opendir_sector:
        .byte 0
dos_opendir_entry:
        .byte 0

//         ========================

        // WARNING: dos_readdir_read_next_entry uses carnal knowledge about the following
        //          structure, particularly the length as calculated here:
        //
        .label dos_dirent_structure_length = 64+1+11+4+4+1

        // Current long filename (max 64 bytes)
        //
dos_dirent_longfilename:
        ascii("Venezualen casaba melon productio") // 33-chars
        ascii("n statistics (2012-2015).txt  ")    // 30-chars
        .byte 0

dos_dirent_longfilename_length:
        .byte 0

dos_dirent_shortfilename:
        .text "FILENAME.EXT"
        .byte 0

dos_dirent_cluster:
        .byte 0,0,0,0

dos_dirent_length:
        .byte 0,0,0,0

dos_dirent_type_and_attribs:
        .byte 0

//         ========================

        // Requested file name and length
        //
dos_requested_filename_len:
        .byte 0

dos_requested_filename:
        ascii("Venezualen casaba melon productio")
        ascii("n statistics (2007-2011).txt     ")

//         ========================

        // Details about current DOS request
        //
dos_sectorsread:                .word 0
dos_bytes_remaining:            .word 0,0
dos_current_sector:             .word 0,0
dos_current_cluster:            .word 0,0
dos_current_sector_in_cluster:  .byte 0

// Current file descriptors
// Each descriptor has:
//   disk id : 1 byte ($00-$07 = file open, $FF = file closed)
//   access mode : 1 byte ($00 = read only)
//   start cluster : 4 bytes
//   current cluster : 4 bytes
//   current sector in cluster : 1 byte
//   offset in sector: 2 bytes
//   file offset / $100 : 3 bytes
//
        .label dos_filedescriptor_max = 4
        .label dos_filedescriptor_offset_diskid = 0
        .label dos_filedescriptor_offset_mode = 1
        .label dos_filedescriptor_offset_startcluster = 2
        .label dos_filedescriptor_offset_currentcluster = 6
//
// These last three fields must be contiguous, as dos_open_current_file
// relies on it.
//
        .label dos_filedescriptor_offset_sectorincluster = 10
        .label dos_filedescriptor_offset_offsetinsector = 11
        .label dos_filedescriptor_offset_fileoffset = 13

dos_file_descriptors:
        .byte $FF,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0        // each is 16 bytes
        .byte $FF,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte $FF,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte $FF,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

    // The current file descriptor
    //
dos_current_file_descriptor:
        .byte 0

    // Offset of current file descriptor
    //
dos_current_file_descriptor_offset:
        .byte 0

//         ========================

    // For providing feedback on why DOS calls have failed
    // There is a set of error codes defined in hyppo_dos.asm
dos_error_code:
        .byte $00

    // Similarly for system partition related errors
syspart_error_code:
        .byte $00

    // Non-zero if there is a valid system partition
syspart_present:
        .byte $00

/*  -------------------------------------------------------------------
    Reserved space for Hypervisor Process work area $BD00-$BDFF
    ---------------------------------------------------------------- */
        .segment ProcessDescriptors
        * = ProcessDescriptors_Start
#import "process_descriptor.asm"



	
