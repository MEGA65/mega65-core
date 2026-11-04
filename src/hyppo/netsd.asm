;; SD card over Ethernet (MEGA65/mega65-core#965)
;;
;; Called once the real card's partitions have been scanned (and so its
;; config sector applied).  When the config sector has a host number for the
;; network card ($031) and DIP switch 8 is on, or right shift is held, the
;; network card (sd_eth, in the native SD controller) is switched on: it
;; takes slot 0's place.  It is initialised (HELLO to the PC running
;; netsd.py) and, if that works, its partitions are scanned in place of the
;; real card's: it then has the disks, the system partition (freeze slots)
;; and so on.  Its system partition's config sector is not applied: the real
;; card's has been.
;;
;; If there is no answer, the network card is switched off again, the bus we
;; booted from is selected, and booting goes on from the real card.  If right
;; shift is (still) held, we say so and wait for it to be released first, so
;; that a failure the user asked for is seen.
;;
;; $D6F1 (see sd_eth.vhdl): 24 writes of 7 bits (bit 7 clear) shift in the
;; flags (8 bits), the key (16 bytes) and 32 bits of entropy, most significant
;; first; a write of $80 + host number switches it on, $80 alone off.
;;
;; Config sector (CONFIGURE's Network tab, page 2, as text): $030 bit 0
;; encrypt as well as sign, $031-$033 the host number (1-127) in decimal,
;; $040-$05F the key as 32 hex digits (none: no signing).

netsd_boot:
        ;; asked for?  DIP switch 8, or right shift held
        lda $d69d
        bmi netsd_asked
        lda buckykey_status
        and #$02
        bne netsd_asked
        rts
netsd_asked:
        lda netsd_cfg_octet
        and #$7f
        bne netsd_configured
        ldx #<msg_netsd_nocfg
        ldy #>msg_netsd_nocfg
        jsr printmessage
        jmp netsd_release_wait
netsd_configured:
        ldx #<msg_netsd_try
        ldy #>msg_netsd_try
        jsr printmessage

        ;; the bus we booted from ($D680 bit 7)
        lda $d680
        and #$80
        sta netsd_bus

        ;; flags, key and entropy, most significant byte first
        lda netsd_cfg_flags
        sta netsd_sr
        ldx #15
netsd_keycopy:
        lda netsd_cfg_key,x
        sta netsd_sr+1,x
        dex
        bpl netsd_keycopy
        ;; entropy: the hardware RNG, mixed with the raster (the hardware also
        ;; mixes in a cycle count)
        ldx #3
netsd_entropy:
        ldy #$00
netsd_rng_wait:
        lda $d7fe
        bpl netsd_rng_ready
        dey
        bne netsd_rng_wait
netsd_rng_ready:
        lda $d7ef
        eor $d012
        sta netsd_sr+17,x
        dex
        bpl netsd_entropy

        ;; 168 bits into $D6F1, 7 at a time
        ldy #24
netsd_group:
        lda #7
        sta netsd_bits
        lda #$00
netsd_bit:
        ;; shift the 21 bytes left a bit: the top one goes into A
        ldx #20
        asl netsd_sr,x
netsd_rol:
        dex
        bmi netsd_rolled
        rol netsd_sr,x
        bra netsd_rol
netsd_rolled:
        rol
        dec netsd_bits
        bne netsd_bit
        sta $d6f1
        dey
        bne netsd_group
        ;; (the key is in the hardware now: don't leave it lying about)
        ldx #20
        lda #$00
netsd_wipe:
        sta netsd_sr,x
        dex
        bpl netsd_wipe

        ;; on, with our host number
        lda netsd_cfg_octet
        ora #$80
        sta $d6f1
        ;; is it there? (on reads back in bit 7)
        lda $d6f1
        bmi netsd_present
        ldx #<msg_netsd_absent
        ldy #>msg_netsd_absent
        jsr printmessage
        jmp netsd_release_wait
netsd_present:
        ;; the network card is slot 0: initialise it (HELLO)
        lda #$c0
        sta $d680
        lda #$00
        sta $d680
        lda #$01
        sta $d680
        lda #$05
        sta netsd_tries
netsd_wait:
        jsr sd_wait_for_boot_card
        bcs netsd_up
        bit $d680
        bvs netsd_failed
        dec netsd_tries
        bne netsd_wait
        bra netsd_failed
netsd_up:
        lda $d6f1
        and #$40
        beq netsd_failed

        ldx #<msg_netsd_ok
        ldy #>msg_netsd_ok
        jsr printmessage
        jsr sd_map_sectorbuffer
        ;; its partitions in place of the real card's
        lda #$00
        sta syspart_present
        lda #$01
        sta netsd_skip_config
        jsr dos_clearall
        jsr dos_read_partitiontable
        lda #$00
        sta netsd_skip_config
        rts

netsd_failed:
        ldx #<msg_netsd_fail
        ldy #>msg_netsd_fail
        jsr printmessage
        ;; off: slot 0 is the internal card again
        lda #$80
        sta $d6f1
        lda netsd_bus
        bne netsd_back_external
        ;; the internal slot's state went with the network card's init:
        ;; initialise the internal card again
        lda #$c0
        sta $d680
        lda #$00
        sta $d680
        lda #$01
        sta $d680
        jsr sd_wait_for_boot_card
        bra netsd_back
netsd_back_external:
        lda #$c1
        sta $d680
netsd_back:
        jsr sd_map_sectorbuffer

netsd_release_wait:
        ;; asked for with right shift: wait until it is let go, so that the
        ;; message is seen (straight through if it isn't held)
        lda buckykey_status
        and #$02
        beq netsd_done
        ldx #<msg_netsd_release
        ldy #>msg_netsd_release
        jsr printmessage
netsd_release_loop:
        lda buckykey_status
        and #$02
        bne netsd_release_loop
netsd_done:
        rts

;; called by syspart_configsector_apply: keep what we need of the config
        ;; sector (in the sector buffer at $DE00), which CONFIGURE keeps as
        ;; text: $031-$033 the host number in decimal, $040-$05F the key in hex
        ;; (none: no signing), $030 bit 0 encrypt as well
netsd_keep_config:
        ;; the host number: up to 3 decimal digits, 1-127
        lda #$00
        sta netsd_cfg_octet
        ldy #$00
netsd_dec:
        lda $de31,y
        sec
        sbc #$30
        bcc netsd_dec_done
        cmp #10
        bcs netsd_dec_done
        sta netsd_tmp
        lda netsd_cfg_octet
        cmp #13                         ;; (x10 would pass 127)
        bcs netsd_dec_bad
        asl
        sta netsd_tmp2
        asl
        asl
        clc
        adc netsd_tmp2
        adc netsd_tmp
        bmi netsd_dec_bad
        sta netsd_cfg_octet
        iny
        cpy #$03
        bne netsd_dec
        bra netsd_dec_done
netsd_dec_bad:
        lda #$00
        sta netsd_cfg_octet
netsd_dec_done:

        ;; the key: 32 hex digits, two to a byte; it ends at the first
        ;; character that isn't one (the rest is zero)
        ldx #15
        lda #$00
netsd_key_clear:
        sta netsd_cfg_key,x
        dex
        bpl netsd_key_clear
        sta netsd_cfg_flags
        ldy #$00
netsd_hex:
        lda $de40,y
        jsr netsd_nybble
        bcs netsd_hex_done
        sta netsd_tmp
        tya
        lsr
        tax
        bcs netsd_hex_low
        lda netsd_tmp
        asl
        asl
        asl
        asl
        sta netsd_cfg_key,x
        bra netsd_hex_next
netsd_hex_low:
        lda netsd_cfg_key,x
        ora netsd_tmp
        sta netsd_cfg_key,x
netsd_hex_next:
        ;; a key: sign, and encrypt if asked for
        lda $de30
        and #$01
        asl
        ora #$01
        sta netsd_cfg_flags
        iny
        cpy #32
        bne netsd_hex
netsd_hex_done:
        rts

        ;; A: a hex digit character ('0'-'9', 'A'-'F' in either case, ASCII
        ;; or PETSCII) -> its value, C clear; C set if it isn't one
netsd_nybble:
        cmp #$3a
        bcs netsd_nybble_letter
        sec
        sbc #$30
        bcc netsd_nybble_bad
        clc
        rts
netsd_nybble_letter:
        cmp #$41
        bcc netsd_nybble_bad
        and #$07
        beq netsd_nybble_bad
        cmp #$07
        beq netsd_nybble_bad
        adc #$09                        ;; (C clear) 'A' = 1 -> 10
        clc
        rts
netsd_nybble_bad:
        sec
        rts

msg_netsd_try:          !text "NETWORK SD CARD: CONNECTING"
                        !8 0
msg_netsd_ok:           !text "NETWORK SD CARD: CONNECTED"
                        !8 0
msg_netsd_fail:         !text "NETWORK SD CARD: NO ANSWER, USING SD CARD"
                        !8 0
msg_netsd_absent:       !text "NETWORK SD CARD: NOT IN THIS CORE"
                        !8 0
msg_netsd_nocfg:        !text "NETWORK SD CARD: NO HOST NUMBER (CONFIGURE)"
                        !8 0
msg_netsd_release:      !text "RELEASE RIGHT SHIFT TO CONTINUE"
                        !8 0

netsd_cfg_flags:        !8 0
netsd_cfg_octet:        !8 0
netsd_cfg_key:          !fill 16, 0
netsd_sr:               !fill 21, 0
netsd_bus:              !8 0
netsd_tries:            !8 0
netsd_skip_config:      !8 0
netsd_tmp:              !8 0
netsd_bits:             !8 0
netsd_tmp2:             !8 0
