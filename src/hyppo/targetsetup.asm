        ;; Setup functions for MEGAphone.
        ;; Basically setup the I2C IO expanders with sensible values, turning
        ;; all peripherals on.

targetspecific_setup:

	;; Setup common I2C area 32-bit pointer
        lda #<$7000
        sta zptempv32+0
        lda #>$7000
        sta zptempv32+1
        lda #<$0FFD
        sta zptempv32+2
        lda #>$0FFD
        sta zptempv32+3
	
	;; Apply I2C settings based on target ID
	lda $d629
	cmp #$03
	beq mega65r3_i2c_setup
	lda $d629
	and #$e0
	cmp #$20
	beq megaphone_i2c_setup
	rts
	
mega65r3_i2c_setup:	

        lda #>$7100
        sta zptempv32+1
        lda #$00
        sta $d020
        ldy #$00

mps3_loop:
        lda mega65r3_i2c_settings,y
        cmp #$ff
        bne +
        ldz #$00

        rts
+
        taz
        iny
        lda mega65r3_i2c_settings,y
        iny


        ;; Keep writing it until it gets written
-
 	sta [<zptempv32],z

	inc $d020	
        cmp [<zptempv32],z
        bne -

        jmp mps3_loop
	
megaphone_i2c_setup:

        ;; Start with backscreen very dim, to avoid inrush current
        ;; causing FGPA power rail to sag.
        lda #$01
        sta $d6f0
	
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

mega65r3_i2c_settings:	
        ;; Speaker amplifier configuration
        !8 $e1,$FF   ;; Left volume initial mute
        !8 $e2,$FF   ;; Right volume initial mute
        !8 $dc,$20
        !8 $dd,$00
        !8 $de,$02
        !8 $df,$00
        !8 $e0,$10
        !8 $e3,$80
        !8 $e4,$0C
        !8 $e5,$99
        !8 $e1,$20   ;; Left volume set ($FF = mute, $40 = full volume, $00 = +24dB)
        !8 $e2,$20   ;; Right volume set ($FF = mute, $40 = full volume, $00 = +24dB)


        !8 $FF,$FF ;; End of list marker
