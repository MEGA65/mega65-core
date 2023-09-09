;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */

        ;; Return the next free task ID
        ;; XXX - Task ID $FF is hypervisor/operating system
        ;; XXX - For now just lie, and always say task $00 is next.
        ;; We should have a process allocation table that we consult.
        ;; (actual suspended processes should be held on SD card in files)

task_get_next_taskid:

        lda #$00
        rts

;;         ========================

task_set_c64_memorymap:

        ;; set contents of CPU registers for exit from hypervisor mode

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
        lda #$f7     ;; All flags except decimal mode
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
        sta hypervisor_iomode    ;; C64 IO map

        ;; Unmap SD sector buffer
        lda #$82
        sta $D680

        ;; Unmap 2nd KB colour RAM
        lda #$01
        trb $d030

	;; Clear 16-bit text mode, but keep CRT emulation and horizontal filter settings
	lda #$d7
        trb $d054	
	
        ;; 40 column mode normal C64 screen
        lda #$00
        sta $d030
        sta $d031
        lda $dd00
        ora #$03
        sta $dd00
        lda #$c0    ;; also enable raster delay to match rendering with interrupts more correctly
        sta $d05d
        lda #$1b
        sta $d011
        lda #$c8
        sta $d016
        lda #$14
        sta $d018

        ;; XXX - disable C65 ROM maps
        rts

;;         ========================

task_set_pc_to_reset_vector:

        ;; Set PC from $FFFC in ROM, i.e., $802FFFC
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

;;         ========================

        ;; Set dummy C64 NMI vector
        ;; This avoid a nasty crash if NMI is called during hyppo
        ;; Points to a RTI instruction in $FEC1

task_dummy_nmi_vector:

        lda #<$FEC1
        sta $0318
        lda #>$FEC1
        sta $0319
        rts

;;         ========================

        ;; Set all page entries and current page number to all zeroes
        ;; so that we don't think any page is loaded.
        ;; XXX - Is all zeroes the best value here?  Physical page 0 is $00000000, which
        ;; is in chipram. It might be legitimate to try to map that.  Perhaps we should set
        ;; the pages to $FFFF instead (but that would reduce available VM space by 16KB).
        ;; Physical page 0 is probably reasonable for now. We can revisit as required.

task_clear_pagetable:

        lda #$00
        ldx #<hypervisor_vm_currentpage_lo
tcp1:   sta $d600,x
        inx
        cpx #<hypervisor_vm_pagetable3_physicalpage_hi+1
        bne tcp1
        rts

;;         ========================

task_erase_processcontrolblock:

        ;; Erase process control block
        ;;
        ldx #$00
        txa
tabs1:        sta currenttask_block,x
        inx
        bne tabs1
        jsr task_clear_pagetable

        ;; Mark all files as closed

        jmp dos_clear_filedescriptors

;;         ========================

task_new_processcontrolblock:

        jsr task_erase_processcontrolblock
        jsr task_get_next_taskid
        sta currenttask_id
        rts

;;         ========================

        ;; Initialise memory to indicate a new blank task.
        ;; (actually, it will be a task preconfigured for C64/C65 mode)

task_asblankslate:

        jsr task_new_processcontrolblock

        jsr task_set_c64_memorymap
        rts

task_set_as_system_task:
	;; Task ID is reserved for the hypervisor and its helpers, and prevents freezing
	lda #$ff
	sta currenttask_id
	rts
	
;;         ========================

ethernet_remote_trap:
	;; By sending a magic ethernet key press frame while the 2nd dip switch is set
	;; will cause this trap to occur, if the key code is 1111111111111 (which
	;; corresponds to no real key.
	;; In response to this, we setup C64 mode, load ETHLOAD.M65 and then exit to it,
	;; effectively passing control to the contents of the following ethernet frames.
        jsr dos_clear_filedescriptors
        jsr task_get_next_taskid
        sta currenttask_id
        jsr task_set_c64_memorymap

        ldx #<txt_ETHLOAD
        ldy #>txt_ETHLOAD
        jsr dos_setname

        ;; bring directory back to root, just in-case user loaded a .d81 from another directory
        ldx dos_default_disk
        jsr dos_cdroot

        ;; Prepare 32-bit pointer for loading etherload at $FF87F00,	
	;; This location is the last 256 bytes of the 32KB colour RAM we
	;; can assume all models possess, and should result in the code not
	;; getting in the way of loading programs of almost any size.
        ;;
	lda #$00
        sta <dos_file_loadaddress+0
        lda #$7f
        sta <dos_file_loadaddress+1
        lda #$f8
        sta <dos_file_loadaddress+2
	lda #$0f
        sta <dos_file_loadaddress+3

@tryAgain:
        jsr dos_readfileintomemory
        inc $d020
        bcc @tryAgain
        dec $d020

        jsr task_set_c64_memorymap
        jsr task_dummy_nmi_vector

	;; Now enable MAP of colour RAM at $8000-$9FFF
	;; $FF87F00 - $8000 = $FF7FF00
	lda #$ff
	sta hypervisor_maphimb
	sta hypervisor_maphilo
	lda #$17
	sta hypervisor_maphihi

	
        ;; set entry point to $8000, i.e, the start
	;; of the 8KB block of colour RAM we map at $8000-$9fff
        lda #<$8000
        sta hypervisor_pcl
        lda #>$8000
        sta hypervisor_pch

	jmp safe_exit_to_loaded_program
	
unstable_illegal_opcode_trap:
kill_opcode_trap:
	;; For now, just launch the freezer if an illegal opcode is hit that
	;; we can't work with.
	;; (Ideally later we will allow some clever tricks with at least the KIL
	;; opcodes, e.g., to call the hypervisor from C64 mode)

	;; FALL THROUGH
	
restore_press_trap:

	;; Check if we are already in the freezer?
	lda currenttask_id
	cmp #$ff
	bne non_hypervisor_task

	;; Don't allow freezing if we are in a hypervisor task
        sta hypervisor_enterexit_trigger

non_hypervisor_task:	
	
        ;; Clear colour RAM at $DC00 flag, as it causes no end of trouble
        lda #$01
        trb $D030
	;; and DMA audio
	lda #$00
	sta $d711

        ;; Freeze to slot 0
	tax ;;   <- uses $00 in A from above
	tay ;;   <- uses $00 in A from above
        jsr freeze_to_slot

	;; Now mark that we are in a system task, so that the freezer can't be frozen
	jsr task_set_as_system_task
	
        ;; Load freeze program
        jsr attempt_loadcharrom
        jsr attempt_loadc65rom

        ldx #<txt_FREEZER
        ldy #>txt_FREEZER
        jsr dos_setname

        ;; TODO: preserve current directory, so that we can restore it later

        ;; bring directory back to root, just in-case user loaded a .d81 from another directory
        ldx dos_default_disk
        jsr dos_cdroot

        ;; Prepare 32-bit pointer for loading freezer program ($000007FF)
        ;; (i.e. $0801 - 2 byte header, so we can use a normal PRG file)
        ;;
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

        ;; set entry point and memory config
        lda #<2061
        sta hypervisor_pcl
        lda #>2061
        sta hypervisor_pch

safe_exit_to_loaded_program:	
        ;; Make $FFD2 vector at $0326 point to an RTS, so that if the freezer
        ;; is built using CC65's C64 profile, the call to $FFD2 to set lower-case mode
        ;; doesn't do something terrible.
        lda #<$03FF
        sta $0326
        lda #>$03FF
        sta $0327
        lda #$60 ;; = RTS
        sta $03FF

        ;; Similarly neuter IRQ/BRK and NMI vectors, in part because the call to $FFD2 above
        ;; will do a CLI, and thus any pending IRQ will immediately trigger, and since the freezer
        ;; is running without the kernal initialising things, it would otherwise use the IRQ
        ;; vector from whatever was being frozen.  Clearly this is a bad thing.
        lda #<$03FC
        sta $0314
        sta $0316
        sta $0318
        lda #>$03FC
        sta $0315
        sta $0317
        sta $0319
        lda #$4C   ;; JMP $EA81
        sta $03FC
        lda #<$EA81
        sta $03FD
        lda #>$EA81
        sta $03FE

        ;; Disable IRQ/NMI sources
        lda #$7f
        sta $DC0D
        sta $DD0D
        lda #$00
        sta $D01A

        ;; return from hypervisor, causing freeze menu to start
        ;;
        sta hypervisor_enterexit_trigger

;;         ========================

protected_hardware_config:

        ;; store config info passed from register a
        lda hypervisor_a
        sta hypervisor_secure_mode_flags

        ;; bump border colour so that we know something has happened
        ;;

        sta hypervisor_enterexit_trigger

;;         ========================

matrix_mode_toggle:

        lda hypervisor_secure_mode_flags
        ;; We want to toggle bit 6 only.
        eor #$40
        sta hypervisor_secure_mode_flags

        sta hypervisor_enterexit_trigger
