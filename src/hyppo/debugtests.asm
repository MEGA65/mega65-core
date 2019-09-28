/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.

    This file is included in hyppo.a65 in the reset_entry routine.
    i.e., anything put here is executed before reset resumes.
    It is used for debugging various things using GHDL simulation,
    because the simulation is so slow, we want things to run instantly.
    ---------------------------------------------------------------- */

.macro i2cperiph() {
        lda #$00
        sta $f0
        lda #$70
        sta $f1
        lda #$FD
        sta $f2
        lda #$0F
        sta $F3
        ldz #$00
i2cl1:  nop
        lda_bp_z($f0)
        inz
        bne i2cl1
}
// i2cperiph()

.macro bitplane_test() {
        lda #$22
        sta $d033
        sta $d034
        lda #$44
        sta $d035
        sta $d036
        lda #$66
        sta $d037
        sta $d038
        lda #$88
        sta $d039
        sta $d03a
        lda #$ff
        sta $d032
        lda #$10
        tsb $d031
@bploop:
        inc $d020
        jmp @bploop
}
// bitplane_test()

.macro vfpga_addressing() {
        // Create pointer to $FFDF000
        lda #<$F000
        sta $02+0
        lda #>$F000
        sta $02+1
        lda #<$0FFD
        sta $02+2
        lda #>$0FFD
        sta $02+3

        // Try reading and writing a register
        ldz #$00
        nop
        lda_bp_z($02)
        ldz #$05
        nop
        sta_bp_z($02)

        // Try writing bitstream config
        lda #$12
        ldz #$15
        nop
        sta_bp_z($02)
        lda #$34
        nop
        sta_bp_z($02)

        ldz #$00
}
// vfpga_addressing()

.macro dmapalettetest() {
        lda $d1ff
        lda $d1fe
        lda $d1fd
        lda $d1fc

        lda $d100
        lda $d101
        lda $d102
        lda $d103

        // put some values in the palette area to make it obvious
        ldx #$00
!:      txa
        sta $d100,x
        inx
        bne !-

        // Copy from $FFD3100
        lda #$0f
        sta hickupdmalist+2
        lda #<$FD3100
        sta hickupdmalist+9
        lda #>$FD3100
        sta hickupdmalist+10
        lda #$FD
        sta hickupdmalist+11

        // Copy to $1100
        lda #$00
        sta hickupdmalist+4
        lda #<$001100
        sta hickupdmalist+12
        lda #>$001100
        sta hickupdmalist+13
        lda #$00
        sta hickupdmalist+14

        // Copy $300 bytes
        lda #<$0300
        sta hickupdmalist+7
        lda #>$0300
        sta hickupdmalist+8

        lda #$ff
        sta $d702
        sta $d704
        lda #>hickupdmalist
        sta $d701
        lda #<hickupdmalist
        sta $d705

!:      inc $d020
        jmp !-
}
// dmapalettetest()

.macro alphatest() {
        // 16-bit text mode, alpha blend enable
        lda #$85
        sta $d054
        jmp *
}
// alphatest()

.macro cpupersonalitytest() {
        // Set up a little routine to run in 6502 CPU personality
        lda #<$4000
        sta hypervisor_pcl
        lda #>$4000
        sta hypervisor_pch
        lda #$00
        sta hypervisor_maplohi

        // DMA copy the routine into place
        //
        lda #$ff
        sta $d702
        lda #$ff
        sta $d704  // dma list is in top MB of address space
        lda #>debugdmalist
        sta $d701
        // Trigger enhanced DMA
        lda #<debugdmalist
        sta $d705

        // Exit to hypervisor
        sta hypervisor_enterexit_trigger

debugdmalist:
        // MEGA65 Enhanced DMA options
        .byte $0A  // Request format is F018A
        .byte $80,$FF // Source is $FFxxxxx
        .byte $81,$00 // Destination is $00xxxxx
        .byte $00  // No more options
        // F018A DMA list
        // (MB offsets get set in routine)
        .byte $00 // copy + last request in chain
        .word theroutine_len // size of copy
        .word theroutine // source is in hyppo
        .byte $0F   // of bank $F
        .word $4000 // destination address is $4000
        .byte $00   // of bank $0
        .word $0000 // modulo (unused)

theroutine:
        // This routine gets copied in to $4000, so we can't
        // easily use jmp or jsr here.  i.e., keep all addresses
        // relative for now.
        inc $d020
        bne theroutine
        beq theroutine

theroutine_end:
        .label theroutine_len = theroutine_end - theroutine
}
// cpupersonalitytest()

.macro buffereduarttest() {
        // 115200 bps for both
        lda #$b2
        sta $D0E6
        sta $D0EE
        lda #$01
        sta $D0EF
        sta $D0E7
        // Hook the two UARTs together
        lda #$11
        sta $D0E2
        sta $D0EA
        // Write a bunch of bytes
        lda #$11
@ll:    sta $D0E8
        clc
        adc #$11
        cmp #$10
        bne @ll
        lda #$00
        tax
        tay
        taz
        // See if they get read correctly
@ll2:   ldx $D0E1
        lda $D0E0
        jmp @ll2
}
// buffereduarttest()

.macro sdtest() {
        // Reset SD card
        lda #$00
        sta sd_ctrl
        lda #$01
        sta sd_ctrl

        // map sector buffer
        lda #$81
        sta sd_ctrl
        // put some data in sector buffer
        ldx #$01
        stx $de00
        inx
        stx $de01
        inx
        stx $de02
        inx
        stx $de03
        lda $de00
        lda $de01
        lda $de02

        // Issue write block command
        lda #$03
        sta sd_ctrl
foo:    jmp foo
}
// sdtest()

.macro f011test() {
        // use real floppy drive
        lda #$01
        sta sd_fdc_select

        // 10x MFM speed for simulation data
        lda #$0a
        sta fdc_mfm_speed

        lda #$68 // floppy motor + LED on, head side 1
        sta $d080

        // Request sector T39,S1,H1
        lda #0
        sta $d084
        lda #1
        sta $d085
        sta $d086

        lda $d087 // clear DRQ flag
        // reset buffer pointers
        lda #$01
        sta $d081

        // Test sector buffer access
        lda #$11
        sta $d087
        lda #$22
        sta $d087
        lda #$01
        sta $d081
        lda $d087
        lda $d087

        // Issue read request
        lda #$40
        sta $d081
bytewait:
        lda $d082
        and #$20
        bne bytewait

        // read next byte
        lda $d087

        // get next byte
        jmp bytewait
}
// f011test()
