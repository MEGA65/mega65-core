;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */
reset_cartridge:
        ldz #$00
        lda #<$0000
        sta zptempv32+0
        sta zptempv32+1
        lda #<$0701
        sta zptempv32+2
        lda #>$0701
        sta zptempv32+3
        lda #$20
        sta [<zptempv32],z
        ldy #$00
charge_delay:
        inz
        bne charge_delay
        iny
        bne charge_delay
        tza
        sta [<zptempv32],z
        rts

setup_for_ultimax_cartridge:
        lda hypervisor_cartridge_flags
        and #$60
        cmp #$40
        beq is_ultimax_cartridge
        rts

is_ultimax_cartridge:
        ;; It's an ultimax cartridge, so we have a couple of things to
        ;; handle differently.
        ;;
        ;; 1. Read reset vector directly from $FFFx, where it will be
        ;;    currently visible.
        ;; 2. Copy $F000-$FFFF to $3xxx, $7xxx, $Bxxx and $Fxxx in 1st
        ;;    64KB of RAM to simulate the way that a C64 makes the top
        ;;    4KB of Ultimax mode ROMs visible to the VIC-II at these
        ;;    locations.
        ;;
        ;; This means copying from $701Fxxx to $000{3,7,B,F}xxx, as DMA
        ;; doesn't see mapped ROMs.
        ;;
        ;; (We  use one list 4x with different destination, as it uses
        ;; less bytes than a chained DMA list with all four.)
        lda reset_vector
        sta hypervisor_pcl
        lda reset_vector+1
        sta hypervisor_pch

        ;; Use DMA to quickly do the copy
        lda #>ultimaxsetup_dmalist
        sta $d701
        lda #$0f
        sta $d702 ;; DMA list is $xxFxxxx
        lda #$ff
        sta $d704 ;; DMA list address is $FFxxxxx

        ;; Run list 4 times with different destination addresses
        lda #$30
        ldx #<ultimaxsetup_dmalist
ultimax_setup_loop:
        sta ultimaxsetup_destination+1

        ;; Trigger MEGA65 enhanced DMA
        stx $d705
        clc
        adc #$40
        cmp #$30
        bne ultimax_setup_loop

        rts

ultimaxsetup_dmalist:
        ;; MEGA65 Enhanced DMA options
        !8 $80,$70   ;; copy from $70xxxxx
        !8 $81,$00   ;; copy to $01xxxxx
        !8 $00       ;; end of options

        ;; F018A dma list
        !8 $00       ;; COPY, no chain
        !16 $1000     ;; 4KB

        ;; source address
        !16 $F000     ;; source is $xxxF000
        !8 $01       ;; source is $xx1xxxx

ultimaxsetup_destination:
        !16 $3000     ;; destination is $xxx3000 (gets changed by routine above)
        !8 $00       ;; destination is $xx03000
        !8 $00,00    ;; Modulo
