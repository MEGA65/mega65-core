;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */

version_sentinel_str = "VRS"
version = 1

freeze_to_slot:
        ;; Freeze current running process to the specified slot

        ;; Slot in XXYY

        jsr syspart_locate_freezeslot
        bcs freeze_save_to_sdcard_immediate
        rts

freeze_save_to_sdcard_immediate:

        ;; Save the current process to the SD card. $D681-4 are expected to
        ;; already be pointing to the first sector of the freeze slot

        ;; Stash SD card registers to scratch area
        ;; (also stashed $D070 which gets mushed by palette saving)
        jsr copy_sdcard_regs_to_scratch

        ;; Save current SD card sector buffer contents
        jsr freeze_write_first_sector_and_wait

        ;; Save each region in the list
        ldx #$00
freeze_next_region:
        jsr freeze_save_region
        txa
        clc
        adc #$08
        tax
        lda freeze_mem_list+7,x
        cmp #$ff
        bne freeze_next_region

        jsr freeze_end_multi_block_write

        rts

unfreeze_load_from_sdcard_immediate:

        ;; Restore a frozen process from the SD card. $D681-4 are expecxted to
        ;; already be pointing to the first sector of the freeze slot

        ;; Skip the first sector of the frozen program which is the
        ;; contents of the SD card sector buffer prior to freezing.
        ;; (We will load it in as the very last thing)
        jsr sd_inc_sectornumber

        ;; Save each region in the list
        ldx #$00

unfreeze_next_region:

        ;; Require SHIFT press and release between every sector for debug
;;         jsr wait_on_shift_key

        ;; Not sure why this delay is necessary, but it is.
        ;; Maybe restoring SD card IO registers causes it to go busy for a while?
        jsr sd_wait_for_ready_reset_if_required

        jsr unfreeze_load_region

        ;; Re-enable M65 IO in case we wrote over the key register during the region unfreeze
        ;; NOTE: This usage was re-instated after deleting it cause exiting the freeze-menu to
        ;; either stall in BASIC (in an endless loop awaiting for the sd-card to be ready) for
        ;; some users, or causing DIR to return 'Drive not ready' for other users.
        ;; The exact reason behind the impact of its removal isn't known and warrants further
        ;; investigation at some stage. See this past Discord thread for more details:
        ;; https://discord.com/channels/719326990221574164/791383472853614593/982994187681161278
        lda #$47
        sta $d02f
        lda #$53
        sta $d02f

        txa
        clc
        adc #$08
        tax
        lda freeze_mem_list+7,x
        cmp #$ff
        bne unfreeze_next_region

        ;; Fix mounted D81, in case it has moved on the SD card since program was frozen

        ;; 1. Detach
        jsr dos_d81detach

        ;; 2. Copy filename for image 0
        ldx currenttask_d81_image0_namelen
        beq noD81Image0ToRemount
        ldx #0
copy:   lda currenttask_d81_image0_name,x
        sta dos_requested_filename,x
        inx
        cpx currenttask_d81_image0_namelen
        bne copy
        lda #0
        sta dos_requested_filename,x
        stx dos_requested_filename_len

        ;; 3. Remember write-enable flag
        lda currenttask_d81_image0_flags
        and #d81_image_flag_write_en
        pha

        ;; 4. Try to reattach it
        jsr dos_d81attach0

        ;; 5. Mark write enabled if required
        pla
        cmp #$00
        beq noD81Image0ToRemount

        ;; 6. Re-enable write access on the disk image
        jsr dos_d81write_en

noD81Image0ToRemount:

        ;; 2. Copy filename for image 0
        ldx currenttask_d81_image1_namelen
        beq noD81Image1ToRemount
        ldx #0
copy1:  lda currenttask_d81_image1_name,x
        sta dos_requested_filename,x
        inx
        cpx currenttask_d81_image1_namelen
        bne copy1
        lda #0
        sta dos_requested_filename,x
        stx dos_requested_filename_len

        ;; 3. Remember write-enable flag
        lda currenttask_d81_image1_flags
        and #d81_image_flag_write_en
        pha

        ;; 4. Try to reattach it
        jsr dos_d81attach1

        ;; 5. Mark write enabled if required
        pla
        cmp #$00
        beq noD81Image1ToRemount

        ;; 6. Re-enable write access on the disk image
        jsr dos_d81write_en

noD81Image1ToRemount:

        ;; Turn SID volume registers back on, as those registers
        ;; cannot be frozen.
        lda #$0f
        sta $D418
	sta $D438
        sta $D458
	sta $D478

        rts

unfreeze_read_sector_and_wait:


;;         jsr debug_show_sector

@retryRead:
        jsr sd_wait_for_ready_reset_if_required

        lda #$02
        sta $d680

        jsr sd_wait_for_ready
        bcc @retryRead

        ;; Read succeeded, so advance sector number, and return
        ;; success

        ;; Increment freeze slot sector number
        jsr sd_inc_sectornumber

        sec

        rts

freeze_write_first_sector_and_wait:

        inc $d020

        ;; Require SHIFT press and release between every sector for debug
;;         jsr wait_on_shift_key

        lda #$00
        sta freeze_write_tries+0
        sta freeze_write_tries+1

@retryWrite1:

        jsr sd_wait_for_ready_reset_if_required

        ;; Trigger the write of the first sector of a multi-sector write
	jsr sd_open_write_gate
        lda #$04
        sta $d680

        jsr sd_wait_for_ready
        jmp @wroteOk1

        inc freeze_write_tries+0
        bne @retryWrite1
        inc freeze_write_tries+1
        bne @retryWrite1

@wroteOk1:
        dec $d020

        ;; Increment freeze slot sector number
        jsr sd_inc_sectornumber

        sec
        rts

freeze_write_sector_and_wait:

        inc $d020

        ;; Require SHIFT press and release between every sector for debug
;;         jsr wait_on_shift_key

        lda #$00
        sta freeze_write_tries+0
        sta freeze_write_tries+1

@retryWrite:

        jsr sd_wait_for_ready_reset_if_required

        ;; Trigger the write (subsequent sector of multi-sector write)
	jsr sd_open_write_gate
        lda #$05
        sta $d680

        jsr sd_wait_for_ready
        jmp @wroteOk

        inc freeze_write_tries+0
        bne @retryWrite
        inc freeze_write_tries+1
        bne @retryWrite

@wroteOk:
        dec $d020

        ;; Increment freeze slot sector number
        jsr sd_inc_sectornumber

        sec
        rts

freeze_end_multi_block_write:
        jsr sd_wait_for_ready
	jsr sd_open_write_gate
        lda #$06
        sta $d680
        jsr sd_wait_for_ready
        rts

freeze_write_tries:
        !16 $0

freeze_save_region:
        ;; X = offset into freeze_mem_list

        ;; Check if end of list, if so, do nothing and return
        lda freeze_mem_list+7,x
        cmp #$ff
        bne fsr1
        rts
fsr1:

        ;; Call setup routine to make any special preparations
        ;; (eg copying data out of non-memory mapped areas, or collecting
        ;; various groups of data together)
        phx
        tax
        jsr dispatch_freeze_prep
        plx

        ;; Get address of region
        lda freeze_mem_list+0,x
        sta freeze_region_dmalist_source_start+0
        lda freeze_mem_list+1,x
        sta freeze_region_dmalist_source_start+1

        ;; Source address is 32-bit, and we need bits 20-27
        ;; for the source MB (upper 4 bits are ignored)
        lda freeze_mem_list+2,x
        lsr
        lsr
        lsr
        lsr
        sta freeze_region_dmalist_source_mb
        lda freeze_mem_list+3,x
        asl
        asl
        asl
        asl
        ora freeze_region_dmalist_source_mb
        sta freeze_region_dmalist_source_mb

        ;; Bank is a bit fiddly: Lower nybl is bits
        ;; 16-19 of address.  Then we have to add the IO flag
        ;; The IO flag is used if the source MB value = $FF.
        ;; However, because we use 28-bit addresses for everything
        ;; the IO bit should be zero, as should the other special
        ;; bits.

        lda freeze_mem_list+2,X
        and #$0f
        sta freeze_region_dmalist_source_bank

        ;; At this point, we have the DMA list source setup.

        ;; Point the destination to the SD card direct job
        ;; sector buffer ($FFD6E00).
        lda #$00
        sta freeze_region_dmalist_dest_start+0
        lda #$6E
        sta freeze_region_dmalist_dest_start+1
        lda #$0D
        sta freeze_region_dmalist_dest_bank
        lda #$ff
        sta freeze_region_dmalist_dest_mb

        ;; Now DMA source and destination addresses have been set
        ;; We now need to step through the region $200 bytes at a
        ;; time, until there are no bytes left.
        ;; If the length is $0000 initially, then it means 64KB.
        ;; The tricky bit is for regions <$200 bytes long, as we need
        ;; to make sure we don't copy more than we should (it could
        ;; be from Hypervisor memory, for example, or to some
        ;; important IO registers, such as the Hypervisor enter/exit
        ;; trap).

        ;; Get length of region
        lda freeze_mem_list+4,x
        sta freeze_dma_length_remaining+0
        lda freeze_mem_list+5,x
        sta freeze_dma_length_remaining+1
        lda freeze_mem_list+6,x
        and #$7f                              ;; mask out bottom 7 bits, since bit 7 indicates if a region should be skipped in unfreezing
        sta freeze_dma_length_remaining+2

freeze_region_dma_loop:

        jsr set_dma_length_based_on_freeze_dma_length_remaining

        ;; Then make sure that there are still bytes to copy.
        ;; If not, then we are done with this block.
        ora freeze_dma_length_remaining+0
        ora freeze_dma_length_remaining+2
        beq freeze_region_dma_done

@freezeExecuteDMA:

        ;; Execute DMA job
        lda #$ff
        sta $d702
        sta $d704
        lda #>freeze_region_dmalist
        sta $d701
        lda #<freeze_region_dmalist
        sta $d705

        ;; Write SD-card direct sector buffer to freeze slot
        ;; Flash a different colour while actually writing sector
        inc $d020

        jsr freeze_write_sector_and_wait

        dec $d020

        ;; Check if remaining length is negative or zero. If so, stop
        jsr is_freeze_dma_length_remaining_zero_or_negative
        beq freeze_region_dma_done

        ;; DMA count is set, subtract from remaining length
        jsr subtract_freeze_dma_size_from_length_remaining

        jsr is_freeze_dma_length_remaining_zero_or_negative
        beq freeze_region_dma_done

        ;; advance source address
        lda freeze_region_dmalist_source_start+1
        clc
        adc #$02
        sta freeze_region_dmalist_source_start+1
        lda freeze_region_dmalist_source_bank
        adc #$00
        sta freeze_region_dmalist_source_bank

        jmp freeze_region_dma_loop

freeze_region_dma_done:
        rts

is_freeze_dma_length_remaining_zero_or_negative:
        lda freeze_dma_length_remaining+2
        bmi @negativeSize
        ora freeze_dma_length_remaining+1
        ora freeze_dma_length_remaining+0
        rts
@negativeSize:
        lda #$00
        rts

subtract_freeze_dma_size_from_length_remaining:
        sec
        lda freeze_dma_length_remaining+0
        sbc freeze_region_dmalist_count+0
        sta freeze_dma_length_remaining+0
        lda freeze_dma_length_remaining+1
        sbc freeze_region_dmalist_count+1
        sta freeze_dma_length_remaining+1
        lda freeze_dma_length_remaining+2
        sbc #$00
        sta freeze_dma_length_remaining+2
        rts

set_dma_length_based_on_freeze_dma_length_remaining:
        lda freeze_dma_length_remaining+1
        and #$fe
        ora freeze_dma_length_remaining+2
        beq @isPartialSector

        ;; At least a whole sector remains
        lda #$00
        sta freeze_region_dmalist_count+0
        lda #$02
        sta freeze_region_dmalist_count+1
        rts

@isPartialSector:
        ;; Set DMA size to remaining bytes
        lda freeze_dma_length_remaining+0
        sta freeze_region_dmalist_count+0
        lda freeze_dma_length_remaining+1
        sta freeze_region_dmalist_count+1
        rts

unfreeze_load_region:
        ;; X = offset into freeze_mem_list

        ;; Check if end of list, if so, do nothing and return
        lda freeze_mem_list+7,x
        cmp #$ff
        beq @dontUnfreeze
        ;; If it is the thumbnail, also don't unfreeze, as it doesn't make sense,
        ;; and the way we freeze the thumbnail means unfreezing would corrupt $1000-$1FFF
        cmp freeze_prep_thumbnail
        bne @doUnfreeze
@dontUnfreeze:
        rts
@doUnfreeze:

        ;; Call setup routine to make any special preparations
        ;; (eg copying data out of non-memory mapped areas, or collecting
        ;; various groups of data together)
        phx
        tax
        jsr dispatch_unfreeze_prep
        plx

        ;; Get address of region
        lda freeze_mem_list+0,x
        sta freeze_region_dmalist_dest_start+0
        lda freeze_mem_list+1,x
        sta freeze_region_dmalist_dest_start+1

        ;; Source address is 32-bit, and we need bits 20-27
        ;; for the source MB (upper 4 bits are ignored)
        lda freeze_mem_list+2,x
        lsr
        lsr
        lsr
        lsr
        sta freeze_region_dmalist_dest_mb
        lda freeze_mem_list+3,x
        asl
        asl
        asl
        asl
        ora freeze_region_dmalist_dest_mb
        sta freeze_region_dmalist_dest_mb

        ;; Bank is a bit fiddly: Lower nybl is bits
        ;; 16-19 of address.  Then we have to add the IO flag
        ;; The IO flag is used if the source MB value = $FF.
        ;; However, because we use 28-bit addresses for everything
        ;; the IO bit should be zero, as should the other special
        ;; bits.

        lda freeze_mem_list+2,X
        and #$0f
        sta freeze_region_dmalist_dest_bank

        ;; At this point, we have the DMA list source setup.

        ;; Point the source to the SD card direct job
        ;; sector buffer ($FFD6E00).
        lda #$00
        sta freeze_region_dmalist_source_start+0
        lda #$6E
        sta freeze_region_dmalist_source_start+1
        lda #$0D
        sta freeze_region_dmalist_source_bank
        lda #$ff
        sta freeze_region_dmalist_source_mb

        ;; Now DMA source and destination addresses have been set
        ;; We now need to step through the region $200 bytes at a
        ;; time, until there are no bytes left.
        ;; If the length is $0000 initially, then it means 64KB.
        ;; The tricky bit is for regions <$200 bytes long, as we need
        ;; to make sure we don't copy more than we should (it could
        ;; be from Hypervisor memory, for example, or to some
        ;; important IO registers, such as the Hypervisor enter/exit
        ;; trap).

        ;; Get length of region
        lda freeze_mem_list+4,x
        sta freeze_dma_length_remaining+0
        lda freeze_mem_list+5,x
        sta freeze_dma_length_remaining+1
        lda freeze_mem_list+6,x
        sta unfreeze_skip
        and #$7f                              ;; mask out bottom 7 bits, since bit 7 indicates if a region should be skipped in unfreezing
        sta freeze_dma_length_remaining+2

unfreeze_region_dma_loop:

        ;; Write SD-card direct sector buffer to freeze slot
        ;; Flash a different colour while actually writing sector
        inc $d020

        jsr unfreeze_read_sector_and_wait

        dec $d020

        jsr set_dma_length_based_on_freeze_dma_length_remaining

        ;; Then make sure that there are still bytes to copy.
        ;; If not, then we are done with this block.
        ora freeze_dma_length_remaining+0
        ora freeze_dma_length_remaining+2
        beq unfreeze_region_dma_done

        bit unfreeze_skip
        bmi @skipDMA

@unfreezeExecuteDMA:
        ;; Execute DMA job
        lda #$ff
        sta $d702
        sta $d704
        lda #>freeze_region_dmalist
        sta $d701
        lda #<freeze_region_dmalist
        sta $d705

@skipDMA:
        ;; Check if remaining length is negative or zero. If so, stop
        jsr is_freeze_dma_length_remaining_zero_or_negative
        beq unfreeze_region_dma_done

        ;; DMA count is set, subtract from remaining length
        jsr subtract_freeze_dma_size_from_length_remaining

        jsr is_freeze_dma_length_remaining_zero_or_negative
        beq unfreeze_region_dma_done

        ;; advance destination address
        lda freeze_region_dmalist_dest_start+1
        clc
        adc #$02
        sta freeze_region_dmalist_dest_start+1
        lda freeze_region_dmalist_dest_bank
        adc #$00
        sta freeze_region_dmalist_dest_bank

        jmp unfreeze_region_dma_loop

unfreeze_region_dma_done:

        ;; Call postfix routine for the region just loaded
        phx
	pha

        lda freeze_mem_list+7,x
        tax
        jsr dispatch_unfreeze_post

	pla
        plx


        rts


dispatch_freeze_prep:
        ;; X = Freeze prep ID byte
        ;; (all of which are even, so that we can use an indirect
        ;; X indexed jump table to efficiently do the dispatch)

        jmp (freeze_prep_jump_table,x)

dispatch_unfreeze_prep:
        ;; X = Freeze prep ID byte
        ;; (all of which are even, so that we can use an indirect
        ;; X indexed jump table to efficiently do the dispatch)

        jmp (unfreeze_prep_jump_table,x)

dispatch_unfreeze_post:
        ;; X = Freeze prep ID byte
        ;; (all of which are even, so that we can use an indirect
        ;; X indexed jump table to efficiently do the dispatch)

        jmp (unfreeze_post_jump_table,x)

do_unfreeze_post_restore_sd_buffer_and_regs:
        ;; Copy back the registers from $D680 - $D70F *excluding*
        ;; $D700 and $D705 (which would trigger a DMA)
        ;; $D680 (which could trigger an SD read or write)

        ;; The data should have been put for us at $FFD6200-$FFD628F
        ;; The contents of the SD sector buffer for restoration should
        ;; be at $FFD6000-$FFD61FF

        lda #<$6200
        sta <dos_scratch_vector+0
        lda #>$6200
        sta <dos_scratch_vector+1
        lda #<$0FFD
        sta <dos_scratch_vector+2
        lda #>$0FFD
        sta <dos_scratch_vector+3

        ;; Copy $D680 - $D70F, which covers both regions of interest
        ldz #$8F
@zz2:   tza
        tax
        lda [<dos_scratch_vector],z
        cpx #$00  ;; $D680
        beq @dontWriteHotRegister
        cpx #$80  ;; $D700
        beq @dontWriteHotRegister
        cpx #$85  ;; $D705
        beq @dontWriteHotRegister

        sta $d680,x

@dontWriteHotRegister:
        dex
        dez
        cpz #$ff
        bne @zz2
        ldz #$00

do_unfreeze_prep_restore_sd_buffer_and_regs:
        ;; But there is nothing we need to do in preparation to unfreezing
        ;; such a region, so just tie it to an RTS
        rts

do_freeze_prep_thumbnail:
        ;; Read the 4KB hardware thumbnail from $D640 and write it to $1000-$1FFF
        ;; We can in principle use a fixed-source DMA to do this.

        ;; set up our pointer for writing
        lda #<$1000
        sta <dos_scratch_vector+0
        lda #>$1000
        sta <dos_scratch_vector+1
        ldy #$00
        ldx #$10

        ;; Set pointer to $FFD2640 to access thumbnail generator.
        ;; This is because the thumbnail generator lives at $D640 which overlaps
        ;; with the hypervisor trap registers when in hypervisor mode.
        ;; We previously had the thumbnail generator mapped at $D63x, but that
        ;; was causing CS glitching that was messing up reading from the C65 UART
        ;; registers.  So now we have moved it to this magic space
        lda #<$2640
        sta zptempv32+0
        lda #>$2640
        sta zptempv32+1
        lda #<$0FFD
        sta zptempv32+2
        lda #>$0FFD
        sta zptempv32+3

        ;; First, make sure the read pointer is at the start of the thumbnail
        ldz #$00
        ;; Then advance pointer address to $D641
        lda [<zptempv32],z
        lda #<$2641
        sta zptempv32+0

@thumbfetchloop:
        lda [<zptempv32],z
        sta (<dos_scratch_vector),y
        iny
        bne @thumbfetchloop
        inc <dos_scratch_vector+1
        dex
        bne @thumbfetchloop

        rts

do_freeze_prep_stash_sd_buffer_and_regs:
        ;; Stash the SD and DMAgic registers we use to actually save
        ;; the machine state.
        ;; DMAgic registers have to get copied without using DMA, so
        ;; that we don't corrupt the registers.
        lda #<$6200
        sta <dos_scratch_vector+0
        lda #>$6200
        sta <dos_scratch_vector+1
        lda #<$0ffd
        sta <dos_scratch_vector+2
        lda #>$0ffd
        sta <dos_scratch_vector+3

        ;; Copy $D680 - $D70F, which covers both regions of interest
        ldz #$8f
@zz:    tza
        tax
        lda $d680,x
        sta [<dos_scratch_vector],z
        dex
        dez
        cpz #$ff
        bne @zz
        ldz #$00

        ;; Now DMA copy the SD sector buffer from $FFD6e00 to
        ;; $FFD6000.
        ;; XXX Replace this (And the above!) with a fixed DMA list. It will be shorter and faster
        lda #$ff
        sta freeze_region_dmalist_source_mb
        sta freeze_region_dmalist_dest_mb
        lda #$8d
        sta freeze_region_dmalist_source_bank
        sta freeze_region_dmalist_dest_bank
        lda #<$6e00
        sta freeze_region_dmalist_source_start+0
        lda #>$6e00
        sta freeze_region_dmalist_source_start+1
        lda #<$6000
        sta freeze_region_dmalist_dest_start+0
        lda #>$6000
        sta freeze_region_dmalist_dest_start+1
        lda #<$0200
        sta freeze_region_dmalist_count+0
        lda #>$0200
        sta freeze_region_dmalist_count+1

        ;; Execute DMA job
        lda #$ff
        sta $d702
        sta $d704
        lda #>freeze_region_dmalist
        sta $d701
        lda #<freeze_region_dmalist
        sta $d705

do_freeze_prep_none:
        rts

;; Jump table of routines to be called before saving specific regions
freeze_prep_jump_table:
        !16 do_freeze_prep_none
        !16 do_freeze_prep_palette_select
        !16 do_freeze_prep_palette_select
        !16 do_freeze_prep_palette_select
        !16 do_freeze_prep_palette_select
        !16 do_freeze_prep_stash_sd_buffer_and_regs
        !16 do_freeze_prep_none
        !16 do_freeze_prep_viciv
	!16 do_freeze_prep_none
	!16 do_freeze_prep_none

;; Jump table of routines to be called before restoring specific regions
;; (the same region list is used for freeze and unfreeze, so the jump
;; tables for unfreezing mirror those used during freezing. The only difference
;; is we require two sets of jump tables for unfreezing, as sometimes we have
;; to prepare the memory map before restoring, and sometimes we have to move
;; the restored data to the correct place in memory after restoration.
unfreeze_prep_jump_table:
        ;; SD card buffer and regs get restored in post routine
        !16 do_unfreeze_prep_none
        !16 do_unfreeze_prep_palette_select
        !16 do_unfreeze_prep_palette_select
        !16 do_unfreeze_prep_palette_select
        !16 do_unfreeze_prep_palette_select
        ;; SD card buffer and regs get restored in post routine
        !16 do_unfreeze_prep_none
        ;; thumbnail doesn't get restored at all
        !16 do_unfreeze_prep_none
        ;; VIC-IV regs need nothing special before unfreezing
        !16 do_unfreeze_prep_none
	;; No prior preparation required for handling hyperregs
	!16 do_unfreeze_prep_none
	;; Nothing required before restoring CHAR ROM
	!16 do_unfreeze_prep_none

unfreeze_post_jump_table:
        !16 do_unfreeze_post_scratch_to_sdcard_regs
        !16 do_unfreeze_post_none
        !16 do_unfreeze_post_none
        !16 do_unfreeze_post_none
        !16 do_unfreeze_post_none
        ;; Don't actually restore the SD card registers until the very end.
        ;; For a start, it will result in totally the wrong SD sector address being there
        ;; when we go to read the next sector!
;;         !16 do_unfreeze_post_restore_sd_buffer_and_regs
        !16 do_unfreeze_post_none
        !16 do_unfreeze_post_none
        !16 do_unfreeze_post_none
	;; No prior preparation required for handling hyperregs
	!16 do_unfreeze_post_hyperregs
	;; Nothing required after restoring CHAR ROM
	!16 do_unfreeze_post_none

do_unfreeze_prep_none:
do_unfreeze_post_none:
        ;; This just needs to have an RTS, so we use one from the end of this
        ;; routine.
        rts

do_unfreeze_post_scratch_to_sdcard_regs:
        ;; Check that we have a version, then only copy stuff we actually saved for
        ;; that version.
        ldx #0
-       lda freeze_version,x
        cmp version_sentinel,x
        bne @rts  ; pre-versioned or corrupt freeze
        inx
        cpx #len(version_sentinel_str)
        bne -

        ;; Version sentinal checks out
        ldy freeze_version,x  ; actual version of this freeze
        ;; when there are future versions this code would look like:
;;        cpy #3
;;        bne +
;;        ;; Do stuff added for version 3 and skip over next cmp
;;        lda freeze_blah
;;        sta $XXXX
;;        dey
;;+       cpy #2
;;        bne +
;;        lda freeze_blerg
;;        sta $XXXX
;;        ;;... etc
;;        dey
;;+       cmp #1
        lda freeze_vic_errata
        sta $d08f
@rts    rts

do_unfreeze_post_hyperregs:
	;; XXX For reasons unknown, the DMA restoration of the hypervisor registers
	;; messes up $D651.
	;; At the point that this fix-up routine is called, the SD card sector
	;; containing the data is available, and so we can simply fix the problem
	;; by copying $ffd6e11 to $ffd3651
	;; If problems later occur for other regs in this range, we can just
	;; make a 32-bit ZP indirect copy loop, since there is some claim that
	;; DMA writing to those registers is problematic.

        ;; that we don't corrupt the registers.
        lda #<$6e11
        sta <dos_scratch_vector+0
        lda #>$6e11
        sta <dos_scratch_vector+1
        lda #<$0ffd
        sta <dos_scratch_vector+2
        lda #>$0ffd
        sta <dos_scratch_vector+3

        ldz #$00
        lda [<dos_scratch_vector],z
	sta $d651

	rts




copy_sdcard_regs_to_scratch:
        ;; Copy the main SD card access registers to a
        ;; scratch area, so that we can save them, and thus restore
        ;; them after unfreezing.
        ;; (This is done outside of the automatic loop, because
        ;; it has to be handled specially.)
        ldx #$0f
dfp1:   lda $d680,x
        sta freeze_scratch_area,x
        dex
        bpl dfp1
        ;; Also save $D070 (palette select register)
        ;; since it gets stomped while saving palettes
        lda $d070
        sta freeze_d070
        ;; Also save $D08F (VIC IV Errata)
        ;; We can't extend the VIC IV DMA entry due to
        ;; it spanning $D081 which must not be written to
        ;; lest the SD reading is disturbed.
        lda $d08f
        sta freeze_vic_errata
        rts

version_sentinel: !text version_sentinel_str
freeze_scratch_area:
        !8 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
freeze_d070:
        !8 0
freeze_version:
        !text version_sentinel_str
        ;; *** NOTE: Update the version constant if more values are added to be restored from
        ;; the scratch area.  This prevents us restoring values that were not
        ;; actually frozen but just happened to be in a freeze sector when an
        ;; older freeze was made.
        !8 version
freeze_vic_errata:
        !8 0
        ;; If adding more values here, update the version constant
freeze_scratch_area_end:

do_freeze_prep_viciv:
        ;; Restore saved $D070 value to fix that $D070 will have been
        ;; stomped over by the palette saving routines
        lda freeze_d070
        sta $d070
        rts

freeze_region_dmalist:
        !8 $0A ;; F011A format DMA list
        !8 $80 ;; Source MB option follows
freeze_region_dmalist_source_mb:
        !8 $00
        !8 $81 ;; Dest MB option follows
freeze_region_dmalist_dest_mb:
        !8 $00
        !8 $00 ;; end of enhanced DMA option list

        ;; F011A format DMA list
        !8 $00 ;; copy + last request in chain
freeze_region_dmalist_count:
        !16 $0000 ;; size of copy
freeze_region_dmalist_source_start:
        !16 $0000 ;; source address lower 16 bits
freeze_region_dmalist_source_bank:
        !8 $00   ;;
freeze_region_dmalist_dest_start:
        !16 $0000
freeze_region_dmalist_dest_bank:
        !8 $00
        !16 $0000 ;; modulo (unused)

do_unfreeze_prep_palette_select:
        ;; We do the same memory map setup during freeze and unfreeze
do_freeze_prep_palette_select:
        ;; X = 6, 8, 10 or 12
        ;; Use this to pick which of the four palette banks
        ;; is visible at $D100-$D3FF
        txa
        clc
        sbc #freeze_prep_palette0
        asl
        asl
        asl
        asl
        asl
        ora #$3f  ;; keep displaying the default palette
        sta $d070
        rts

wait_on_shift_key:
        lda $d611
        beq wait_on_shift_key
-       lda $d611
        bne -
        rts

debug_show_sector:
        ;; XXX DEBUG
        lda $d681
        sta $0800
        lda $d682
        sta $0801
        lda $d683
        sta $0802
        lda $d684
        sta $0803
        rts

syspart_read_freeze_region_list_trap:
        ;; Copy freeze_mem_list out to user memory
        ldx hypervisor_x
        stx <dos_scratch_vector+0
        lda hypervisor_y
        and #$7f ;; don't allow writing over hypervisor or IO when copying it out
        sta <dos_scratch_vector+1
        ldx #freeze_mem_list_end-freeze_mem_list
        ldy #$00
-       lda freeze_mem_list,y
        sta (<dos_scratch_vector),y
        iny
        dex
        bne -
        jmp return_from_trap_with_success

freeze_mem_list:
	;; XXX - There must not be more than 32 of these, as the region list
	;; has to fit within a single page.

        ;; start address (4 bytes), length (3 bytes),
        ;; preparatory action required before reading/writing (1 byte)
        ;; Each segment will live in its own sector (or sectors if
        ;; >512 bytes) when frozen. So we should avoid excessive
        ;; numbers of blocks.

        ;; core SDcard registers we need to be ready to start writing
        ;; sectors. We copy these out and in manually at the start
        ;; and end of the freeze and unfreeze routines, respectively.
        ;; So they are not done here.
        ;; (the +$FFF0000 is to rebase the pointer into the hypervisor memory area)
        !32 freeze_scratch_area+$fff0000
        !16 (freeze_scratch_area_end - freeze_scratch_area)
        !8 0
        !8 freeze_prep_none

        ;; SDcard sector buffer + SD card registers
        ;; We have to save this before anything much else, because
        ;; we need it for freezing.  We stash $FFD6E00-FFF and
        ;; $FFD3680-70F at $FFD6000 before hand, so that we preserve
        ;; these registers before touching them.
        ;; (the DMAgic registers at $DDF370x have to get copied manually,
        ;; so that we don't mess up the DMA state.  Also, when restoring
        ;; we have to take some care putting them back exactly.)

        !32 $ffd6000
        !16 $0090
        !8 0
        !8 freeze_prep_stash_sd_buffer_and_regs

        ;; SDcard sector buffer (F011)
        !32 $ffd6c00
        !16 $0200
        !8 0
        !8 freeze_prep_none

        ;; Process decriptor
        !32 $fffbd00
        !16 $0100
        !8 0
        !8 freeze_prep_none

        ;; $D640-$D67E hypervisor state registers
        ;; XXX - These can't be read by DMA, so we need to have a
        ;; prep routine that copies them out first?
        !32 $ffd3640
        !16 $003e
        !8 0
        !8 freeze_prep_hyperregs

        ;; VIC-IV palette block 0
        ;; Each prep routine changes which palette is visible at ffd3100.
        !32 $ffd3100
        !16 $0300
        !8 0
        !8 freeze_prep_palette0

        ;; VIC-IV palette block 1
        !32 $ffd3100
        !16 $0300
        !8 0
        !8 freeze_prep_palette1

        ;; VIC-IV palette block 2
        !32 $ffd3100
        !16 $0300
        !8 0
        !8 freeze_prep_palette2

        ;; VIC-IV palette block 3
        !32 $ffd3100
        !16 $0300
        !8 0
        !8 freeze_prep_palette3

        ;; 32KB colour RAM
        !32 $ff80000
        !16 $8000
        !8 $00
        !8 freeze_prep_none

        ;; CIAs
        !32 $ffd3c00
        !16 $0200
        !8 0
        !8 freeze_prep_none

        ;; VIC-IV $D000-$D07F
        !32 $ffd3000
        !16 $0080   ; Do not increase this. $D081 controls sd card buffers/etc.
        !8 0        ;  writing to it will cause very bad things to happen.
        !8 freeze_prep_viciv

        ;; VIC-IV C128 2MHz enable emulation register
        !32 $ffd0030
        !16 $0001
        !8 0
        !8 freeze_prep_none

        ;; 384KB RAM (includes the 128KB "ROM" area)
        !32 $0000000
        !16 $0000
        !8 6          ;; =6x64K blocks = 384KB
        !8 freeze_prep_none

        ;; Process scratch space
        !32 currenttask_block
        !16 $0100
        !8 0
        !8 freeze_prep_none

        ;; $D700-$D7FF CPU registers (excluding DMAgic registers, which we save/restore along with SD card registers)
        !32 $ffd3710
        !16 $00F0
        !8 0
        !8 freeze_prep_none

        ;; Internal 1541 4KB RAM + 16KB ROM
        ;; XXX - Need to also save state of VIAs
        !32 $FFDB000
        !16 $5000
        !8 0
        !8 freeze_prep_none

	;; Thumbnail is visible always at $FFD4xxx.
	;; This saves some hypervisor code space, by no longer requiring to read it and place it
	;; in low memory somewhere.  It's read-only, so we don't care about attempts to write to
	;; it during unfreezing
        !32 $FFD4000
        !16 $1000
        !8 $80                              ;; bit 7 set in # banks tells unfreezer to ignore it.
        !8 freeze_prep_thumbnail

        ;; Char "ROM"
        !32 $ff7e000
        !16 $1000
        !8 0
        !8 freeze_prep_none

        ;; XXX - Other IO chips!

        ;; End of list
        !32 $FFFFFFFF
        !16 $FFFF
        !8 $FF
        !8 $FF

freeze_mem_list_end:

freeze_dma_length_remaining:
        !8 0,0,0

        ;; If bit 7 set, then don't DMA the region into place on unfreezing
unfreeze_skip:
        !8 0

