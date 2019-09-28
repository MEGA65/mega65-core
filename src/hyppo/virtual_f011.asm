/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */

f011_virtual_read:

        // Reset buffer pointers and stop SD card from reading
        // from card and overwriting what we load
        lda #$01
        sta $D081

        lda #$80
        tsb $D086

        // We write the job details to the uart monitor interface.
        // Assume uart monitor interface is at 2mbits = 20 cycles
        // per char, so we need to add a short delay between each char
        lda $d084
        ora #$80
        sta $d67C

        jsr @wait5usec
        lda $d085
        ora #$80
        sta $D67C

        jsr @wait5usec
        lda $D086
        ora #$80
        sta $D67C

        jsr @wait5usec
        lda #$21
        sta $D67C

        // Wait for monitor_load to clear bit 7 of side register to indicate that
        // it has done the job
fvr3:   lda $d086
        bmi fvr3

fvr_same_as_last_time:
        // Set floppy flags as appropriate to look like FDC has just successfully read a
        // sector
        lda #$35
        sta f011_flag_stomp

        sta hypervisor_enterexit_trigger

@wait5usec:
        // 40MHz = 40 cycles / usec, so we need 200 cycles
        // JSR/RTS is ~10 cycles
        // 64 iterations of 3 cycles = ~192 cycles
        // so should be about right
        ldx #$40
!:      dex
        bne !-
        rts

f011_virtual_write:

        // Reset buffer pointers and stop SD card from reading
        // from card and overwriting what we load
        lda #$01
        sta $D081

        lda #$40
        tsb $D086

        // We write the job details to the uart monitor interface.
        // Assume uart monitor interface is at 2mbits = 20 cycles
        // per char, so we need to add a short delay between each char
        lda $d084
        ora #$80
        sta $d67C

        jsr @wait5usec
        lda $d085
        ora #$80
        sta $D67C

        jsr @wait5usec
        lda $D086
        ora #$80
        sta $D67C

        jsr @wait5usec
        lda #'\'
        sta $D67C

fvw1:   lda $d086
        and #$c0
        bne fvw1

        lda #$16
        sta f011_flag_stomp

        // Return from hypervisor
        //
fvw2:   sta hypervisor_enterexit_trigger

