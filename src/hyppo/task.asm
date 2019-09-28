/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */

        // Return the next free task ID
        // XXX - Task ID $FF is hypervisor/operating system
        // XXX - For now just lie, and always say task $00 is next.
        // We should have a process allocation table that we consult.
        // (actual suspended processes should be held on SD card in files)

task_get_next_taskid:

        lda #$00
        rts

//         ========================

task_set_c64_memorymap:

        // set contents of CPU registers for exit from hypervisor mode

        lda #$00
        sta hypervisor_a
        sta hypervisor_x
        sta hypervisor_y
        sta hypervisor_z
        sta hypervisor_b
        lda #$ff
        sta hypervisor_spl
        lda #$01
        sta hypervisor_sph
        lda #$f7     // All flags except decimal mode
        sta hypervisor_flags
        lda #$00
        sta hypervisor_maplolo
        sta hypervisor_maplohi
        sta hypervisor_maphilo
        sta hypervisor_maphihi
        sta hypervisor_maplomb
        sta hypervisor_maphimb
        lda #$3f
        sta hypervisor_cpuport00
        sta hypervisor_cpuport01

        lda #$00
        sta hypervisor_iomode    // C64 IO map

        // Unmap SD sector buffer
        lda #$82
        sta $D680

        // Unmap 2nd KB colour RAM
        lda #$01
        trb $d030

        // 40 column mode normal C64 screen
        lda #$00
        sta $d030
        sta $d031
        sta $d054
        lda $dd00
        ora #$03
        sta $dd00
        lda #$c0    // also enable raster delay to match rendering with interrupts more correctly
        sta $d05d
        lda #$1b
        sta $d011
        lda #$c8
        sta $d016
        lda #$14
        sta $d018

        // XXX - disable C65 ROM maps
        rts

//         ========================

task_set_pc_to_reset_vector:

        // Set PC from $FFFC in ROM, i.e., $802FFFC
        ldx #<reset_vector
        ldy #>reset_vector
        ldz #$02
        lda #$00
        jsr longpeek
        lda hyppo_scratchbyte0
        sta hypervisor_pcl
        ldx #<reset_vector
        inx
        ldy #>reset_vector
        ldz #$02
        lda #$00
        jsr longpeek
        lda hyppo_scratchbyte0
        sta hypervisor_pch

        rts

//         ========================

        // Set dummy C64 NMI vector
        // This avoid a nasty crash if NMI is called during hyppo
        // Points to a RTI instruction in $FEC1

task_dummy_nmi_vector:

        lda #<$FEC1
        sta $0318
        lda #>$FEC1
        sta $0319
        rts

//         ========================

        // Set all page entries and current page number to all zeroes
        // so that we don't think any page is loaded.
        // XXX - Is all zeroes the best value here?  Physical page 0 is $00000000, which
        // is in chipram. It might be legitimate to try to map that.  Perhaps we should set
        // the pages to $FFFF instead (but that would reduce available VM space by 16KB).
        // Physical page 0 is probably reasonable for now. We can revisit as required.

task_clear_pagetable:

        lda #$00
        ldx #<hypervisor_vm_currentpage_lo
tcp1:   sta $d600,x
        inx
        cpx #[<hypervisor_vm_pagetable3_physicalpage_hi+1]
        bne tcp1
        rts

//         ========================

task_erase_processcontrolblock:

        // Erase process control block
        //
        ldx #$00
        txa
tabs1:        sta currenttask_block,x
        inx
        bne tabs1
        jsr task_clear_pagetable

        // Mark all files as closed

        jmp dos_clear_filedescriptors

//         ========================

task_new_processcontrolblock:

        jsr task_erase_processcontrolblock
        jsr task_get_next_taskid
        sta currenttask_id
        rts

//         ========================

        // Initialise memory to indicate a new blank task.
        // (actually, it will be a task preconfigured for C64/C65 mode)

task_asblankslate:

        jsr task_new_processcontrolblock

        jsr task_set_c64_memorymap
        rts

//         ========================

restore_press_trap:

        // Clear colour RAM at $DC00 flag, as it causes no end of trouble
        lda #$01
        trb $D030

        // Freeze to slot 0
        ldx #$00
        ldy #$00
        jsr freeze_to_slot

        // Load freeze program
        jsr attempt_loadcharrom
        jsr attempt_loadc65rom

        ldx #<txt_FREEZER
        ldy #>txt_FREEZER
        jsr dos_setname

        // Prepare 32-bit pointer for loading freezer program ($000007FF)
        // (i.e. $0801 - 2 byte header, so we can use a normal PRG file)
        //
        lda #$00
        sta <dos_file_loadaddress+2
        sta <dos_file_loadaddress+3
        lda #$07
        sta <dos_file_loadaddress+1
        lda #$ff
        sta <dos_file_loadaddress+0

@tryAgain:
        jsr dos_readfileintomemory
        inc $d020
        bcc @tryAgain
        dec $d020

        jsr task_set_c64_memorymap
        jsr task_dummy_nmi_vector

        // set entry point and memory config
        lda #<2061
        sta hypervisor_pcl
        lda #>2061
        sta hypervisor_pch

        // Make $FFD2 vector at $0326 point to an RTS, so that if the freezer
        // is built using CC65's C64 profile, the call to $FFD2 to set lower-case mode
        // doesn't do something terrible.
        lda #<$03FF
        sta $0326
        lda #>$03FF
        sta $0327
        lda #$60 // = RTS
        sta $03FF

        // Similarly neuter IRQ/BRK and NMI vectors, in part because the call to $FFD2 above
        // will do a CLI, and thus any pending IRQ will immediately trigger, and since the freezer
        // is running without the kernal initialising things, it would otherwise use the IRQ
        // vector from whatever was being frozen.  Clearly this is a bad thing.
        lda #<$03FC
        sta $0314
        sta $0316
        sta $0318
        lda #>$03FC
        sta $0315
        sta $0317
        sta $0319
        lda #$4C   // JMP $EA81
        sta $03FC
        lda #<$EA81
        sta $03FD
        lda #>$EA81
        sta $03FE

        // Disable IRQ/NMI sources
        lda #$7f
        sta $DC0D
        sta $DD0D
        lda #$00
        sta $D01A

        // return from hypervisor, causing freeze menu to start
        //
        sta hypervisor_enterexit_trigger

//         ========================

protected_hardware_config:

        // store config info passed from register a
        lda hypervisor_a
        sta hypervisor_secure_mode_flags

        // bump border colour so that we know something has happened
        //

        sta hypervisor_enterexit_trigger

//         ========================

matrix_mode_toggle:

        lda hypervisor_secure_mode_flags
        // We want to toggle bit 6 only.
        eor #$40
        sta hypervisor_secure_mode_flags

        sta hypervisor_enterexit_trigger
