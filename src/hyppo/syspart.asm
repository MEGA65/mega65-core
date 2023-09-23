;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.

;;    MEGA65 System Partition functions

;;     The system partition (type = $41 = 65) holds several major data
;;     areas:

;;     1. Header, that identifies the version and structure of the system
;;        partition.

;;     2. Frozen programs for task switching.
;;        (Some of which may be reserved by the operating system, e.g., for
;;         alarms and other special purposes.)

;;     3. Installed services that can be requested via the Hypervisor.
;;        These are internally just frozen programs with a valid service
;;        description header.

;;     HEADER - First sector of partition

;;     $000-$00A "MEGA65SYS00" - Magic string and version indication
;;     $010-$017 Start and size (in sectors) of frozen program area
;;     $018-$01b Size of each frozen program slot
;;     $01c-$01d Number of frozen program slots
;;     $01e-$01f Number of sectors used for frozen program directory
;;     $020-$027 Start and size (in sectors) or installed services
;;     $028-$02b Size of each installed service slot
;;     $02c-$02d Number of service slots
;;     $02e-$02f Number of sectors used for slot directory
;;     $030-$1ff RESERVED

;;     Basically we have two main areas in the system partition for frozen
;;     programs, and for each we have a directory that allows for quick
;;     scanning of the lists. Thee goal is to reduce the number of random
;;     seeks (which still have a cost on SD cards, because commencing a
;;     read is much slower than continuing one), and also the amount of
;;     data required. To this end the directory entries consist of a 64
;;     byte name field and a 64 byte reserved field, so that each is 128
;;     bytes in total, allowing 4 per 512 byte sector.

;;     If the first byte of a directory is $00, then the entry is assumed
;;     to be free.
;;     ---------------------------------------------------------------- */

onboarding_dmalist:	
        ;; MEGA65 Enhanced DMA options
        !8 $0A      ;; Request format is F018A
        !8 $80,$00  ;; Copy from $00xxxxx
        !8 $81,$00  ;; Copy to $00xxxxx

	;; Copy program down
        !8 $00 ;; no more options
	;; F018A DMA list
        !8 $00 ;; copy + not chained request
        !16 $77FF ;; size of copy 
        !16 $0000 ;; starting addr 
        !8 $04   ;; of bank $5
        !16 $07FF ;; destination address is $0801 - 2
        !8 $00   ;; of bank $0
        !16 $0000 ;; modulo (unused)


	
launch_onboarding:

	;; DMA copy the onboarding utility into place
        lda #$ff
        sta $d702
        ;; lda #$ff
        sta $d704  ;; dma list is in top MB of address space
        lda #>onboarding_dmalist
        sta $d701
        ;; Trigger enhanced DMA
        lda #<onboarding_dmalist
        sta $d705	
	
	;; Run util from in hypervisor context, similarly to how we run the flash menu
	;; this means the whole thing must be less than ~29KB in size, to not run over
	;; $8000-$BFFF where the hypervisor is mapped
	jmp run_util_in_hypervisor_context
	
syspart_open:
        ;; Open a system partition.
        ;; At this point, only syspart_start_sector and
        ;; syspart_size_in_sectors have been initialised.

        ;; Read First sector of system partition
        ldx #$03
spo1:   lda syspart_start_sector,x
        sta $d681,x
        dex
        bpl spo1

        lda #syspart_error_readerror
        sta syspart_error_code
        jsr sd_readsector
        bcc syspart_openerror

        ;; Got First sector of system partition.

        ;; Check magic string
        lda #syspart_error_badmagic
        sta syspart_error_code
        ldx #10
spo2:	lda $de00,x
        cmp syspart_magic,x
        bne syspart_openerror
        dex
        bpl spo2

        lda #$00
        sta syspart_error_code

        ;; Copy bytes from offset $10 - $2F into syspart_structure
        ;; XXX It is assumed that these fields are aligned with each other
        ldx #$10
spo3:	lda $de00,x
        sta syspart_structure,x
        inx
        cpx #$30
        bne spo3

        ;; Display info about # of freeze and service slots
        ldx #<msg_syspart_info
        ldy #>msg_syspart_info
        jsr printmessage
        ldy #$00
        ldz syspart_freeze_slot_count+1
        jsr printhex
        ldz syspart_freeze_slot_count+0
        jsr printhex
        ldz syspart_service_slot_count+1
        jsr printhex
        ldz syspart_service_slot_count+0
        jsr printhex

        ;; Show size of freeze slots
        ldz syspart_freeze_slot_size_in_sectors+3 
        jsr printhex
        ldz syspart_freeze_slot_size_in_sectors+2
        jsr printhex
        ldz syspart_freeze_slot_size_in_sectors+1
        jsr printhex
        ldz syspart_freeze_slot_size_in_sectors+0
        jsr printhex

        lda #$01
        sta syspart_present

        ldx #<msg_syspart_ok
        ldy #>msg_syspart_ok
        jsr printmessage

        jsr syspart_configsector_read
	lda $de0e
	bpl do_launch_onboarding
no_onboarding:	
        jsr syspart_configsector_apply
        bcs spo4

        ldx #<msg_syspart_config_invalid
        ldy #>msg_syspart_config_invalid
        jsr printmessage

spo4:	sec
        rts
	
syspart_openerror:

        ;; Report error opening system partition
        ldx #<msg_syspart_open_error
        ldy #>msg_syspart_open_error
        jsr printmessage
        ldy #$00
        ldz syspart_error_code
        jsr printhex
        ldz #$00

        clc
        rts

do_launch_onboarding:
	;; Only try onboarding on first boot
	lda first_boot_flag_instruction
	cmp #$4c
	beq no_onboarding
	jmp launch_onboarding
	
        ;; XXX These should return success/failure indication
syspart_configsector_read_trap:
        jsr syspart_configsector_read
        sta hypervisor_enterexit_trigger

syspart_configsector_write_trap:
        jsr syspart_configsector_write
        sta hypervisor_enterexit_trigger

syspart_configsector_set_trap:
        jsr syspart_configsector_set
        sta hypervisor_enterexit_trigger

syspart_configsector_apply_trap:
        jsr syspart_configsector_apply
        sta hypervisor_enterexit_trigger

syspart_unfreeze_from_slot_trap:
        ldx hypervisor_x
        jsr syspart_locate_freezeslot
        jsr unfreeze_load_from_sdcard_immediate

	;; Set task ID to $00 if it was $ff, so that you can't unfreeze something,
	;; and have the hypervisor think that it loaded it
	lda currenttask_id
	cmp #$ff
	bne wasnt_ff
	lda #$00
	sta currenttask_id
wasnt_ff:	
	
	;;  Make sure we resume a frozen program on the same raster line as
	;; it entered the freezer.  This might need a bit of tuning to get
	;; perfect, but it should already be accurate to within one raster line.

	
	lda #$ff
@unfreezesyncwait:
	cmp $d012
	bne @unfreezesyncwait
	;; Clear any pending raster interrupt, to avoid problems.
	dec $d019 
        sta hypervisor_enterexit_trigger

syspart_get_slot_count_trap:
        ldx syspart_freeze_slot_count+0
        stx hypervisor_x
        ldy syspart_freeze_slot_count+1
        sty hypervisor_y
        jmp return_from_trap_with_success

syspart_locate_freezeslot_trap:
        ldx hypervisor_x
        ldy hypervisor_y
        jsr syspart_locate_freezeslot
        sta hypervisor_enterexit_trigger

syspart_locate_freezeslot:
        ;; Get the first sector of a given freeze slot
        ;; X = low byte of slot #
        ;; Y = high byte of slot #

        phx
        phy

        ;; Check that we have a system partition
        lda syspart_present
        bne splf1
        lda #syspart_error_nosyspart
        sta syspart_error_code
        clc
        rts
splf1:
        ;; Check that freeze slot number is not invalid
        cpy syspart_freeze_slot_count+1
        beq sc1
        bcc slotnumok
sc1:	cpx syspart_freeze_slot_count+0
        beq slotbad
        bcc slotnumok
slotbad:
        ;; Report error status for out of bounds slot number
        lda #syspart_error_badslotnum
        sta syspart_error_code
        clc
        rts

slotnumok:

        jsr syspart_locate_freezeslot_0
        ;; Now add freeze slot size x (YYXX) bytes
        ;; Use hardware multiplier to work out slot address

        ;; Set multiplicant inputs to multiplier

        ;; XXX - Works only with SD HC cards!

        ;; SDHC, so unit is sectors, and so is just a case of copying the bytes
        ;; Start by shifting down by 1 byte = /256
        ldx #$03
splf4b:	lda syspart_freeze_slot_size_in_sectors,x
        sta mult48_d0,x
        dex
        bpl splf4b

@multiplierSet:

        plx
        stx mult48_e0
        ply
        sty mult48_e1
        lda #$00
        sta mult48_e2
        sta mult48_e3

        ;; Read out answer, and add it to slot 0 address
        ldx #0
        ldy #3
        clc
splf3:	lda mult48_result0,x
        adc $d681,x
        sta $d681,x
        inx
        dey
        bpl splf3

        sec
        rts

syspart_locate_freezeslot_0:
        ;; Freeze slot #0 starts at:
        ;;   syspart_start_sector + syspart_freeze_area_start
        ;; + syspart_freeze_directory_sector_count
        lda syspart_start_sector+0
        clc
        adc syspart_freeze_area_start+0
        sta $d681
        ldx #1
splf2:	lda syspart_start_sector,x
        adc syspart_freeze_area_start,x
        sta $d681,x
        inx
        cpx #4
        bne splf2
        lda $d681
        clc
        adc syspart_freeze_directory_sector_count+0
        sta $d681
        lda $d682
        adc syspart_freeze_directory_sector_count+1
        sta $d682
        lda $d683
        adc #0
        sta $d683
        lda $d684
        adc #0
        sta $d684

        rts


syspart_configsector_set:
	;; So, the config sector USED to live in the system partition.
	;; But that causes a few problems:
	;; 1. You need a system partition, just to be able to pick PAL or NTSC on start.
	;; 2. The utility menu now, for good reason, appears before trying to probe any
	;;    SD cards. This means that the configure programme couldn't work out the
	;;    correct sector to work on.
	;; As a result, we now just officially have the config sector live in sector 1.
        ldx #3
	lda #0
spcr1:	;; lda syspart_start_sector,x
        sta $d681,x
        dex
        bpl spcr1
        jmp sd_inc_sectornumber

syspart_configsector_read:
        jsr syspart_configsector_set
        jmp sd_readsector

syspart_configsector_write:
        jsr syspart_configsector_set
	jsr write_non_mbr_sector
        sec
        rts

syspart_config_invalid:
        clc
        rts
	
syspart_configsector_apply:
        ;; Check version
        lda $de00
        cmp #$01
        bne syspart_config_invalid
        lda $de01
        cmp #$01
        bne syspart_config_invalid

        ;; Set DMAgic revision
        lda $de20
        sta $d703

	;; Set $D054 options
	;; (eg scanline emulation ($20) and horizontal blur filter ($08))
	lda #$28
	trb $d054
	and $de21
	tsb $d054

        ;; Set PAL/NTSC mode (keeping $D058 value)
        ldx $d058
        lda $d06f
        and #$3f
        sta $d06f
        lda $de02
        and #$c0
        ora $d06f
        sta $d06f
	;; And also write it into the instruction that sets the display mode on reset
	sta pal_ntsc_minus_1+1
        stx $d058

        ;; set CIA TOD50 flag depending on PAL/NTSC
        lda $de02
        and #$80        ; extract flag (1 = NTSC)
        bne @skiptod50  ; already cleared flags, done!
        lda $dc0e
        ora #$80
        sta $dc0e       ; set CIA1:TOD50
        lda $dd0e
        ora #$80
        sta $dd0e       ; set CIA2:TOD50
        bra @skiptod50end
@skiptod50:
        lda $dc0e
        and #$7f
        sta $dc0e       ; clear CIA1:TOD50
        lda $dd0e
        and #$7f
        sta $dd0e       ; clear CIA2:TOD50
@skiptod50end:

        ;; Set audio and related options
	lda $de0d
	sta $d61a
	lda #$00
	sta $d63c
	lda $de22
	beq @sid6581
	lda #$0f
	sta $d63c
@sid6581:
	

	;; Trigger onboarding menu or not
	;; (activated elsewhere)
	// $de0e bit 7
	
	;; Super SFX cartridge emulation
	lda $de0c
	ldz #$00
	lda #$07
	sta zptempv32+3
	ldx #$fe
	stx zptempv32+2
	inx
	stx zptempv32+1
	stx zptempv32+0
	sta [<zptempv32],z	

	;; Audio amplifier control
        lda #$fe
        sta $d6f4 ; select mixer register $fe (audio-amp on/off via bit0)
        lda $de03
        and #$01
        sta $d6f5 ; store audio-amp on/off setting into mixer register $fe

	;; Stereo flags
        lda $de03
        and #$40
        beq is_stereo
        jsr audio_set_mono
        jmp done_audio
is_stereo:
        lda $de03
        and #$20
        bne is_mirrored
        jsr audio_set_stereo
        jmp done_audio
is_mirrored:
        jsr audio_set_stereomirrored
done_audio:

        ;; Set F011 to use 3.5 drive or disk images
        lda $de04
        sta sd_fdc_select

        ;; Enable/disable Amiga mouse support (emulates 1351 mouse)
        lda $de05
        sta mouse_detect_ctrl

	;; Enable/disable experimental long filename support
	lda #$4c 		; Disable LFN support by default
	sta disable_lfn_byte
	lda $de0f
	bpl @nolfn
	;; Diable jump that disables LFN support 
	lda #$2c 		; BIT $xxxx opcode
	sta disable_lfn_byte
@nolfn:
        ;; Copy MAC address
        ldx #$05
maccopy:
        lda $de06, x
        sta mac_addr_0, x
        dex
        bpl maccopy

        ;; Copy default disk image name
        lda $de10
        beq nodiskname
        ldx #$0f
disknamecopy:
        lda	$de10, x
        sta	txt_MEGA65D81, x
        dex
        bpl	disknamecopy
nodiskname:
        sec
        rts

syspart_dmagic_autoset_trap:
        jsr syspart_dmagic_autoset
        sta hypervisor_enterexit_trigger

syspart_dmagic_autoset:
        ;; Set DMAgic revision based on ROM version
        ;; $20017-$2001D = "V9xxxxx" version string.
        ;; If it is 900000 - 910522, then DMAgic revA, else revB
        lda #$16
        sta zptempv32
        lda #$00
        sta zptempv32+1
        sta zptempv32+3
        lda #$02
        sta zptempv32+2
        ldz #$00
        lda [<zptempv32],z
        cmp #$56
        beq @hasC65ROMVersion
        rts
@hasC65ROMVersion:
        ;; Check first digit is 9
        inz
        lda [<zptempv32],z
        cmp #$39
        bne @useDMAgicRevB
        ;; check if second digit is 0, if so, revA
        inz
        lda [<zptempv32],z
        cmp #$30
        beq @useDMAgicRevA
        ;; check if second digit != 1, if so, revB
        cmp #$31
        bne @useDMAgicRevB
        ;; check 3rd digit is 0, if not, revB
        inz
        lda [<zptempv32],z
        cmp #$30
        bne @useDMAgicRevB
        ;; check 4th digit is >5, if so, revB
        inz
        lda [<zptempv32],z
        cmp #$36
        bcs @useDMAgicRevB
        ;; check 4th digit is <5, if so, revA
        cmp #$35
        bcc @useDMAgicRevA
        ;; check 5th digit <=> 2
        inz
        lda [<zptempv32],z
        cmp #$32
        bcc @useDMAgicRevA
        cmp #$33
        bcs @useDMAgicRevB
        ;; check 6th digit <3
        inz
        lda [<zptempv32],z
        cmp #$33
        bcc @useDMAgicRevA
@useDMAgicRevB:
        ldz #$00
        lda #$01
        tsb $d703

        ldx #<msg_dmagicb
        ldy #>msg_dmagicb
        jmp printmessage

@useDMAgicRevA:
        ldz #$00
        lda #$01
        trb $d703

        ldx #<msg_dmagica
        ldy #>msg_dmagica
        jmp printmessage


        ;; Magic string that identifies a MEGA65 system partition
syspart_magic:
        !text "MEGA65SYS00"
msg_syspart_open_error:
        !text "SYSTEM PARTITION ERROR: (ERRNO: $$)"
        !8 0
msg_syspart_ok:
        !text "SYSTEM PARTITION OK"
        !8 0
msg_syspart_info:
        !text "SYS: $$$$ FRZ + $$$$ SVC X $$$$$$$$"
        !8 0
msg_syspart_config_invalid:
        !text "SYSPART CONFIG INVALID. PLEASE SET."
        !8 0
	
syspart_trap:
        sei
        cld
        and #$fe
        tax
        jmp (syspart_trap_table,x)

syspart_trap_table:
        ;; $00-$0E
        !16 syspart_configsector_read_trap
        !16 syspart_configsector_write_trap
        !16 syspart_configsector_apply_trap
        !16 syspart_configsector_set_trap
        !16 syspart_dmagic_autoset_trap
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $10-$1E
        !16 syspart_locate_freezeslot_trap
        !16 syspart_unfreeze_from_slot_trap
        !16 syspart_read_freeze_region_list_trap
        !16 syspart_get_slot_count_trap
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $20-$2E
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $30-$3E
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $40-$4E
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $50-$5E
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $60-$6E
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $70-$7E
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction
