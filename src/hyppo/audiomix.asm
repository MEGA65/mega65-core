/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */
audiomix_setup:

        // Set all audio mixer coefficients to maximum by default
        ldx #$00
        txa // A=$00 = all coefficients zero
aml1:
        jsr audiomix_setcoefficient
        inx
        bne aml1

        // Set master volume to max for L & R channels on M65R2 audio jack
        lda #$ff
        ldx #$fe
        jsr audiomix_set2coefficients
        ldx #$de
        jsr audiomix_set2coefficients
	// And also for speaker / HDMI audio outputs
        ldx #$1e
        jsr audiomix_set2coefficients
        ldx #$3e
        jsr audiomix_set2coefficients

        jmp audio_set_stereo

audio_set_mono:
        // Left and right SID volume levels
        // for stereo operation
        lda #$be
        ldx #$c0
        jsr audiomix_set4coefficients
        ldx #$d0
        jsr audiomix_set4coefficients
        ldx #$f0
        jsr audiomix_set4coefficients
        ldx #$e0
        jsr audiomix_set4coefficients
        ldx #$00
        jsr audiomix_set4coefficients
        ldx #$10
        jsr audiomix_set4coefficients
        ldx #$20
        jsr audiomix_set4coefficients
        ldx #$30
        jsr audiomix_set4coefficients
        rts

audiomix_set_sid_lr_coefficients:
        ldx #$c0
        jsr audiomix_set2coefficients
        ldx #$d0
        jsr audiomix_set2coefficients
        ldx #$e2
        jsr audiomix_set2coefficients
        ldx #$f2
        jsr audiomix_set2coefficients
        ldx #$00
        jsr audiomix_set2coefficients
        ldx #$10
        jsr audiomix_set2coefficients
        ldx #$22
        jsr audiomix_set2coefficients
        ldx #$32
        jmp audiomix_set2coefficients

audiomix_set_sid_rl_coefficients:	
        ldx #$c2
        jsr audiomix_set2coefficients
        ldx #$d2
        jsr audiomix_set2coefficients
        ldx #$e0
        jsr audiomix_set2coefficients
        ldx #$f0
        jsr audiomix_set2coefficients
        ldx #$02
        jsr audiomix_set2coefficients
        ldx #$12
        jsr audiomix_set2coefficients
        ldx #$20
        jsr audiomix_set2coefficients
        ldx #$30
        jmp audiomix_set2coefficients        	
	
audio_set_stereo:
        // Left and right SID volume levels
        // for stereo operation
        lda #$be
	jsr audiomix_set_sid_lr_coefficients
        lda #$40
	jmp audiomix_set_sid_rl_coefficients

audio_set_stereomirrored:
        // Left and right SID volume levels
        // for stereo operation
        lda #$40
	jsr audiomix_set_sid_lr_coefficients
        lda #$be
	jmp audiomix_set_sid_rl_coefficients

audiomix_setcoefficient:
        stx audiomix_addr

        // wait 17 cycles before writing (16 + start of read instruction)
        // to give time to audio mixer to fetch the 16-bit coefficient, before
        // we write to half of it (which requires the other half loaded, so that the
        // write to the 16-bit register gets the correct other half).
        // note that bit $1234 gets replaced in hyppo by monitor_load when doing
        // hot-patching, so we can't use that instruction for the delay

        // simple solution: write to address register several times to spend the time.
        // 16 cycles here. then the sta of the data gives us 3 more cycles, so we are fine.
        stx audiomix_addr
        stx audiomix_addr
        stx audiomix_addr
        stx audiomix_addr

        // update coefficient
        sta audiomix_data
        rts

audiomix_set4coefficients:
        jsr audiomix_setcoefficient
        inx
        jsr audiomix_setcoefficient
        inx
audiomix_set2coefficients:
        jsr audiomix_setcoefficient
        inx
        jmp audiomix_setcoefficient
