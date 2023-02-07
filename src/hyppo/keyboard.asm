;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */

;; peek first key in accelerated key buffer, without removing it
;; carry set if not key found (A is 0 in that case)
;; keycode is in accumulator
peekkeyboard:
        ;; We now use hardware-accelerated keyboard reading
        lda ascii_key_in
        cmp #$00
        beq nokey
        clc
        rts
nokey:  ;; no key currently down, so set carry and return
        sec
        rts

;; get first key from accelerated key buffer, removing it from queue
;; accumulater holds key
;; carry set if no key was in buffer (A is 0 in that case)
scankeyboard:
        jsr peekkeyboard
        bcs nokey
        ;; clear key from buffer
        sta ascii_key_in
        clc
        rts
