/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */
audiomix_setup:

        // Set all audio mixer coefficients to maximum by default
        ldx #$00
        lda #$30
aml1:
        jsr audiomix_setcoefficient
        inx
        bne aml1

        // Enable audio amplifier for Nexys4 series boards
        ldx #$fe
        lda #$01
        jsr audiomix_setcoefficient

        // For modem1 output, just have the SIDs at a reasonable volume, plus microphone

        // Zero out all inputs for line out, but set to max for modem1 output
        ldx #$40
        lda #$00
aml2:   jsr audiomix_setcoefficient
        inx
        cpx #$60
        bne aml2

        // Then put the SID inputs to a good level for both line out and cellular modem
        ldx #$00
        lda #$80
        jsr audiomix_set4coefficients
        ldx #$40 // and for the cellular modem
        jsr audiomix_set4coefficients

        // Set microphones off for computer (we can make the dialer in the handheld turn them on, or it manually)
        ldx #$14
        lda #$00
        jsr audiomix_set4coefficients
        // but on for the cellular modem
        ldx #$54
        lda #$ff
        jsr audiomix_set4coefficients

        // and set master volume gain for line out to something sensible
        ldx #$1e
        lda #$ff
        jsr audiomix_set2coefficients

        // and set master volume gain for cellular modem to something sensible
        ldx #$5e
        lda #$ff // bit 0 must be set for coefficient $5e, to allow modem to be PCM audio master
        jsr audiomix_set2coefficients
        rts

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
