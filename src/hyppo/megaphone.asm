        ;; Setup functions for MEGAphone.
        ;; Basically setup the I2C IO expanders with sensible values, turning
        ;; all peripherals on.

megaphone_setup:

        ;; Start with backscreen very dim, to avoid inrush current
        ;; causing FGPA power rail to sag.
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

        ;; Detect if we have MEGAphone I2C perihperals or not
        ;; NOTE: It takes a little while for the I2C controller to
        ;; start up.  So we should wait a few milliseconds before
        ;; deciding.
        ;; (This is also why it works when replacing the hypervisor on boot,
        ;; as the replaced version has started late enough.
-       lda $d012
        cmp #$ff
        bne -

        ldz #$1f
        lda #$00
-
        lda (<zptempv32),y
        lda [<zptempv32],z
        bne have_i2cperipherals
        dez
        bne -

        ;; Restore full screen brightness
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
        bne +
        ldz #$00

        ;; Set full brightness on LCD on exit
        lda #$ff
        sta $d6f0

        rts
+
        taz
        iny
        lda megaphone_i2c_settings,y
        iny


        ;; Keep writing it until it gets written
-
        sta [<zptempv32],z

        ;; Wait for I2C register to get written

        inc $d020

        cmp [<zptempv32],z
        bne -


        jmp mps_loop


megaphone_i2c_settings:
        ;; LCD panel
        !8 $16,$40 ;; Port 0 to output, except LCD backlight line, that we now control via an FPGA pin
        !8 $17,$00 ;; Port 1 to output
        !8 $12,$bf ;; Enable power to all sub-systems ($BF = $FF - $40)
        !8 $13,$20 ;; Power up headphones amplifier
	;; FALL THROUGH
mega65r3_i2c_settings:	
        ;; Speaker amplifier configuration
        !8 $35,$FF   ;; Left volume initial mute
        !8 $36,$FF   ;; Right volume initial mute
        !8 $30,$20
        !8 $31,$00
        !8 $32,$02
        !8 $33,$00
        !8 $34,$10
        !8 $37,$80
        !8 $38,$0C
        !8 $39,$99
        !8 $35,$60   ;; Left volume set ($FF = mute, $40 = full volume)
        !8 $36,$60   ;; Right volume set ($FF = mute, $40 = full volume)


        !8 $FF,$FF ;; End of list marker
