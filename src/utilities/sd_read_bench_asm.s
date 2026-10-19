; Identical 6502 polling loop for legacy and native SD controllers.
; Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project. LGPL v3.
        .export _sd_bench_command, _sd_bench_sector, _sd_bench_copy
        .export _sd_bench_irq_save, _sd_bench_irq_restore
        .export _sd_bench_clear, _sd_bench_key, _sd_bench_getkey
        .export _sd_bench_irq_mask
        .importzp sreg

        .segment "BSS"
saved_p:        .res 1
command_frame:  .res 1
copy_buffer:    .res 512

        .segment "CODE"
_sd_bench_irq_save:
        php
        pla
        sta saved_p
        sei
        cld
        rts

_sd_bench_irq_restore:
        lda saved_p
        pha
        plp
        rts

_sd_bench_irq_mask:
        sei
        cld
        rts

_sd_bench_clear:
        lda #147
        jmp $ffd2                     ; KERNAL CHROUT

; Scan the keyboard explicitly: KERNAL IRQs are disabled for benchmarking.
; This pause is outside all timed regions and allows serial screenshots.
_sd_bench_key:
        jsr _sd_bench_getkey
        cmp #32
        bne _sd_bench_key
        rts

; Return any key, including when KERNAL IRQs are disabled.
_sd_bench_getkey:
        jsr $ff9f                     ; SCNKEY
        jsr $ffe4                     ; GETIN
        beq _sd_bench_getkey
        ldx #0
        rts

; fastcall uint32_t: low word A/X, high word sreg/sreg+1.
_sd_bench_sector:
        sta $d681
        stx $d682
        lda sreg
        sta $d683
        lda sreg+1
        sta $d684
        rts

; Return 0 success, 1 controller error, 2 timeout (120 video frames).
_sd_bench_command:
        ldx $d7fa
        stx command_frame
        sta $d680
poll:   lda $d680
        and #$01                      ; foreground command still active?
        bne waiting
        lda $d680
        and #$60                      ; native errors deliberately hold BUSY
        bne failed
        lda $d680
        and #$03
        beq success
waiting: lda $d7fa
        sec
        sbc command_frame
        cmp #120
        bcc poll
        lda #2
        ldx #0
        rts
failed:
        lda #1
        ldx #0
        rts
success:
        lda #0
        ldx #0
        rts

; Physical SD buffer $FFD6E00 -> 512 bytes of application RAM. DMA stalls
; the CPU until completion; its setup and copy cost are part of the timing.
_sd_bench_copy:
        lda #0
        sta $d702
        sta $d704
        lda #>copy_job
        sta $d701
        lda #<copy_job
        sta $d705
        rts

        .segment "DATA"
copy_job:
        .byte $0b, $80, $ff, $81, $00, $00
        .byte $00                     ; copy
        .word 512
        .word $6e00
        .byte $0d                     ; source $FFD6E00
        .word copy_buffer
        .byte $00                     ; destination bank 0
        .byte $00                     ; subcommand
        .word 0                       ; modulo
