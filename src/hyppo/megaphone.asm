        // Setup functions for MEGAphone.
        // Basically setup the I2C IO expanders with sensible values, turning
        // all peripherals on.

megaphone_setup:

        // Start with backscreen very dim, to avoid inrush current
        // causing FGPA power rail to sag.
        lda #$01
        sta $d6f0

        lda #<$7000
        sta zptempv32+0
        lda #>$7000
        sta zptempv32+1
        lda #<$0FFD
        sta zptempv32+2
        lda #>$0FFD
        sta zptempv32+3

        // Detect if we have MEGAphone I2C perihperals or not
        // NOTE: It takes a little while for the I2C controller to
        // start up.  So we should wait a few milliseconds before
        // deciding.
        // (This is also why it works when replacing the hypervisor on boot,
        // as the replaced version has started late enough.
!:      lda $d012
        cmp #$ff
        bne !-

        ldz #$1f
        lda #$00
!:
        lda (<zptempv32),y
        nop
        lda_bp_z(<zptempv32)
        bne have_i2cperipherals
        dez
        bne !-

        // Restore full screen brightness
        lda #$ff
        sta $d6f0

        rts

have_i2cperipherals:
        lda #$00
        sta $d020
        ldy #$00
mps_loop:
        lda megaphone_i2c_settings,y
        cmp #$ff
        bne !+
        ldz #$00

        // Set full brightness on LCD on exit
        lda #$ff
        sta $d6f0

        rts
!:
        taz
        iny
        lda megaphone_i2c_settings,y
        iny


        // Keep writing it until it gets written
!:
        nop
        sta_bp_z(<zptempv32)

        // Wait for I2C register to get written

        inc $d020

        nop
        cmp_bp_z(<zptempv32)
        bne !-


        jmp mps_loop


megaphone_i2c_settings:
        // LCD panel
        .byte $16,$40 // Port 0 to output, except LCD backlight line, that we now control via an FPGA pin
        .byte $17,$00 // Port 1 to output
        .byte $12,$bf // Enable power to all sub-systems ($BF = $FF - $40)
        .byte $13,$20 // Power up headphones amplifier

        // Speaker amplifier configuration
        .byte $35,$FF   // Left volume initial mute
        .byte $36,$FF   // Right volume initial mute
        .byte $30,$20
        .byte $31,$00
        .byte $32,$02
        .byte $33,$00
        .byte $34,$10
        .byte $37,$80
        .byte $38,$0C
        .byte $39,$99
        .byte $35,$60   // Left volume set ($FF = mute, $40 = full volume)
        .byte $36,$60   // Right volume set ($FF = mute, $40 = full volume)


        .byte $FF,$FF // End of list marker
